import XCTest
@testable import EcgCore

/// Python版(kokolog_test の realtime/pipeline.py)の結果と、Swift版の結果が一致するかを確かめる。
/// 正解データは tools_make_fixtures.py で作る(心電図は計算で作った作り物)。
final class AnalysisTests: XCTestCase {
    func fixture(_ name: String) -> String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures").appendingPathComponent(name).path
    }

    func readLines(_ name: String) -> [String] {
        let text = try! String(contentsOfFile: fixture(name), encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: true).map { String($0) }
    }

    func close(_ a: Double, _ b: Double, tol: Double = 1e-6) -> Bool {
        abs(a - b) <= tol * max(1.0, abs(a), abs(b))
    }

    /// 空欄は nil、数値は Double にする
    func cell(_ s: Substring) -> Double? { s.isEmpty ? nil : Double(s) }

    func same(_ a: Double?, _ b: Double?) -> Bool {
        if a == nil && b == nil { return true }
        guard let x = a, let y = b else { return false }
        return close(x, y)
    }

    func testBandPassAndPeaks() {
        let lines = readLines("filter_case.txt")
        let sig = lines[0].split(separator: " ").map { Double($0)! }
        let want = lines[1].split(separator: " ").map { Double($0)! }
        let wantPeaks = lines[2].split(separator: " ").map { Int($0)! }
        let y = BandPass.filtfilt(sig)
        XCTAssertEqual(y.count, want.count)
        var worst = 0.0
        for i in 0..<min(y.count, want.count) { worst = max(worst, abs(y[i] - want[i])) }
        XCTAssertLessThan(worst, 1e-6, "帯域通過フィルタの最大誤差")
        let med = median(y)
        let mad = median(y.map { abs($0 - med) })
        XCTAssertEqual(findPeaks(y, distance: 65, prominence: mad * 4), wantPeaks)
    }

    func testRiRChain() {
        let lines = readLines("rir_case.csv").dropFirst()
        let r = RealtimeRiR()
        var bad = 0
        var checked = 0
        for (i, line) in lines.enumerated() {
            let c = line.split(separator: ",", omittingEmptySubsequences: false)
            let out = r.beat(rtime: Double(c[0])!, rri: Double(c[1])!)
            let ok = same(out?.rir, cell(c[2])) && same(out?.sumrir, cell(c[3])) && same(out?.La, cell(c[4]))
            if !ok {
                bad += 1
                if bad <= 5 { print("RiRの不一致 行\(i): Swift=\(String(describing: out)) 正解=\(line)") }
            }
            if out?.rir != nil { checked += 1 }
        }
        XCTAssertEqual(bad, 0)
        XCTAssertGreaterThan(checked, 1000)
        XCTAssertGreaterThan(r.reseeds, 0)
    }

    func testWholePipeline() {
        let data = FileManager.default.contents(atPath: fixture("synthetic.ecg"))!
        let b = [UInt8](data)
        let gaps = [1200: 400, 1800: 50]          // tools_make_fixtures.py の GAPS と同じ
        let ecg = RealtimeECG()
        for i in 0..<(b.count / 2 / 50) {
            if let g = gaps[i] { ecg.gap(g) }
            var chunk = [Int]()
            for k in (i * 50)..<((i + 1) * 50) { chunk.append(Int(b[2 * k]) | (Int(b[2 * k + 1]) << 8)) }
            ecg.push(chunk)
        }
        let want = readLines("expected_beats.csv").dropFirst().map {
            $0.split(separator: ",", omittingEmptySubsequences: false)
        }
        XCTAssertEqual(ecg.beats.count, want.count, "拍の数")
        var bad = 0
        for i in 0..<min(ecg.beats.count, want.count) {
            let s = ecg.beats[i]
            let w = want[i]
            let ok = s.sampleIndex == Int(w[1])! && close(s.rriMs, Double(w[2])!)
                && same(s.rir, cell(w[4])) && same(s.sumrirPerSpan, cell(w[5])) && same(s.La, cell(w[6]))
            if !ok {
                bad += 1
                if bad <= 5 { print("拍の不一致 \(i): Swift=\(s) 正解=\(w.joined(separator: ","))") }
            }
        }
        XCTAssertEqual(bad, 0, "一致しない拍の数")
        XCTAssertEqual(ecg.droppedClip, 2)

        // 信号品質
        let qw = readLines("quality_case.txt")[0].split(separator: " ")
        let q = ecg.quality()!
        XCTAssertTrue(close(q.mains, Double(qw[0])!), "50Hz混入 \(q.mains)")
        XCTAssertTrue(close(q.noise, Double(qw[1])!), "雑音 \(q.noise)")
        XCTAssertTrue(same(q.qrs, Double(qw[2])), "R波の振幅 \(String(describing: q.qrs))")
        XCTAssertTrue(close(q.rail, Double(qw[3])!))
        XCTAssertEqual(q.level, Int(qw[4])!)
    }

    /// 状態(安静/軽い動き/運動)。心電図とジャイロをパケットの形で順に流し、Python版の結果と比べる。
    func testActivity() {
        func stamp(_ i: Int, _ offset: Int = 0) -> [UInt8] {
            let v = 72000 * 256 + (i * 256) / 5 + offset
            return [UInt8(v / (3600 * 256)), UInt8(v / (60 * 256) % 60), UInt8(v / 256 % 60), UInt8(v % 256)]
        }
        let b = [UInt8](FileManager.default.contents(atPath: fixture("synthetic.ecg"))!)
        let gy = [UInt8](FileManager.default.contents(atPath: fixture("gyro_case.bin"))!)
        var gyro = [[UInt8]: [UInt8]]()            // 本体時刻4バイト → パケット
        for k in 0..<(gy.count / 41) {
            let pkt = Array(gy[(k * 41)..<((k + 1) * 41)])
            gyro[Array(pkt[0..<4])] = pkt
        }
        var skip = Set(1200..<1202)                // tools_make_fixtures.py の SKIP_ECG と同じ
        skip.formUnion(1800..<1808)
        let states: [ActivityState] = [.rest, .light, .exercise, .unknown]
        let want = readLines("activity_expected.csv").dropFirst().map {
            $0.split(separator: ",", omittingEmptySubsequences: false)
        }
        let session = EcgSession()
        var row = 0
        var bad = 0
        var seen = Set<String>()
        for i in 0..<(b.count / 2 / 50) {
            if let g = gyro[stamp(i, 13)] { session.onGyro(GyroPacket(g)!) }
            if skip.contains(i) { continue }
            let bytes = stamp(i) + Array(b[(i * 100)..<((i + 1) * 100)]) + [0]
            session.onPacket(EcgPacket(bytes)!)
            let w = want[row]
            row += 1
            let a = session.activity
            let ok = Int(w[0])! == i && a.state == states[Int(w[1])!]
                && same(a.motion.isNaN ? nil : a.motion, cell(w[2]))
                && same(a.hr.isNaN ? nil : a.hr, cell(w[3])) && a.hrOk == (w[4] == "1")
            if !ok {
                bad += 1
                if bad <= 5 { print("状態の不一致 \(i): Swift=\(a.state) \(a.motion) \(a.hr) 正解=\(w.joined(separator: ","))") }
            }
            seen.insert(a.state.rawValue)
        }
        XCTAssertEqual(row, want.count)
        XCTAssertEqual(bad, 0, "一致しないパケットの数")
        XCTAssertEqual(seen.count, 4, "4つの状態がすべて出ること")
        XCTAssertEqual(session.lost, 10)
    }

    /// 記録ファイルに書いて流し直すと、直接受信したときと同じ結果になること。末尾が切れていても読めること。
    func testRecordingReplay() {
        let b = [UInt8](FileManager.default.contents(atPath: fixture("synthetic.ecg"))!)
        let direct = EcgSession()
        var file = [UInt8]()
        for i in 0..<1500 {
            let v = 72000 * 256 + (i * 256) / 5
            let stamp: [UInt8] = [UInt8(v / (3600 * 256)), UInt8(v / (60 * 256) % 60), UInt8(v / 256 % 60), UInt8(v % 256)]
            let pkt = stamp + Array(b[(i * 100)..<((i + 1) * 100)]) + [0]
            direct.onPacket(EcgPacket(pkt)!)
            file += Recording.encode(kind: 0x01, pkt)
        }
        file += [0x01, 105, 1, 2, 3]          // 書き込みの途中で終了された件
        let again = EcgSession()
        Recording.replay(file, into: again)
        XCTAssertGreaterThan(direct.ecg.beats.count, 100)
        XCTAssertEqual(again.ecg.beats.count, direct.ecg.beats.count)
        XCTAssertEqual(again.ecg.beats.last?.sampleIndex, direct.ecg.beats.last?.sampleIndex)
        XCTAssertEqual(again.packets, 1500)
    }
}
