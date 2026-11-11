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
    }
}
