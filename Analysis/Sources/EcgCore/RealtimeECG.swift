import Foundation

/// 250Hzの心電図(記録値)を少しずつ受け取り、R波検出 → RRIの補正 → RiR まで計算する。
/// Python版 realtime/pipeline.py の RealtimeECG と同じ手順。
public final class RealtimeECG {
    public let fs: Int
    let win: Int                 // 波形を保持する長さ(10秒)
    let lookahead: Int           // R波の確定を遅らせる長さ(0.6秒)
    let minDistance: Int         // ピーク同士の最小間隔
    let tailBeats: Int
    var m = [Double]()           // 直近 win の5点移動平均後の波形
    var maHist = [Double](repeating: 0, count: 4)
    public private(set) var n = 0            // これまでに受け取ったサンプル数
    public private(set) var f = [Double]()   // 直近 win のフィルタ後の波形
    var adc = [Double]()         // 直近 win の記録値
    var fOff = 0                 // f[0] の通し番号
    var lastConf = -1_000_000_000
    var cand = [Int]()           // ①の後に残ったピーク
    var amp = [Int: Double]()    // ピークの通し番号 → 振幅
    public private(set) var kept = [Int]()   // ②の後に残ったピーク
    var committedSample = -1
    public let rir: RealtimeRiR
    public private(set) var beats = [BeatResult]()
    public private(set) var droppedClip = 0
    public private(set) var gaps = 0
    public private(set) var lostSamples = 0

    public init(fs: Int = 250, hr0: Double = 60.0, validSpan: Double = 120.0, intSpan: Double = 180.0,
                sumrirSpan: Double = 120.0, winSec: Double = 10.0, lookaheadSec: Double = 0.6,
                tailBeats: Int = 300) {
        self.fs = fs
        self.win = Int(winSec * Double(fs))
        self.lookahead = Int(lookaheadSec * Double(fs))
        self.minDistance = Int(Double(fs) * 60.0 / RiRConst.maxHR)
        self.tailBeats = tailBeats
        self.rir = RealtimeRiR(hr0: hr0, validSpan: validSpan, intSpan: intSpan, sumrirSpan: sumrirSpan)
    }

    /// 受け取ったサンプル(uint16。下位14bitが心電図)を足して、解析を進める。
    public func push(_ raw: [Int]) {
        if raw.isEmpty { return }
        let a = raw.map { Double($0 & 0x3FFF) }
        if n == 0 {
            maHist = [Double](repeating: a[0] - 8192, count: 4)
        }
        let x = a.map { $0 - 8192.0 }
        let ext = maHist + x
        // 5点移動平均(過去4点+現在)。250Hzでは50Hzの成分が消える
        var ma = [Double](repeating: 0, count: x.count)
        for i in 0..<x.count {
            ma[i] = (ext[i] + ext[i + 1] + ext[i + 2] + ext[i + 3] + ext[i + 4]) / 5
        }
        maHist = Array(ext[(ext.count - 4)...])
        m.append(contentsOf: ma)
        if m.count > win { m.removeFirst(m.count - win) }
        adc.append(contentsOf: a)
        if adc.count > win { adc.removeFirst(adc.count - win) }
        f = m.count > 60 ? BandPass.filtfilt(m) : m
        n += ma.count
        fOff = n - f.count
        detect()
    }

    /// 受信の欠落。0.5秒以内は直前の値で埋める。それより長いときは波形とピークを捨てて検出をやり直す。
    public func gap(_ missing: Int) {
        if missing <= 0 { return }
        gaps += 1
        if missing <= Int(0.5 * Double(fs)) {
            let last = adc.last ?? 8192.0
            push([Int](repeating: Int(last), count: missing))
            return
        }
        n += missing
        m = []; f = []; adc = []
        fOff = n
        maHist = [Double](repeating: maHist[3], count: 4)
        lastConf = -1_000_000_000
        cand = []; kept = []; amp = [:]
        lostSamples += missing
    }

    /// R波の検出。確定するのは、末尾 lookahead より古いピークだけ。
    func detect() {
        if f.count < fs * 3 { return }
        let med = median(f)
        var mad = median(f.map { abs($0 - med) })
        if mad == 0 { mad = 1.0 }
        let pk = findPeaks(f, distance: minDistance, prominence: mad * 4.0)
        let mask = BeatCleaning.clipDropoutMask(adc, margin: Int((0.15 * Double(fs)).rounded(.toNearestOrEven)))
        var new = false
        for p in pk {
            let g = p + fOff
            if g > n - 1 - lookahead { continue }
            if g - lastConf < minDistance { continue }
            lastConf = g
            if mask[p] {
                droppedClip += 1
                continue
            }
            cand.append(g)
            amp[g] = abs(f[p])
            new = true
        }
        if new { afterNewPeak() }
    }

    /// ②短い偽ピークの除去 → RRI → ③補正 → RiR
    func afterNewPeak() {
        let n0 = cand.count
        if n0 < 6 {
            kept = cand
        } else {
            kept = BeatCleaning.sanitizeCausal(cand, amp: amp, fs: fs, maxRemoved: max(1, Int(Double(n0) * 0.12)))
        }
        let k = kept
        if k.count < 2 { return }
        let lo = max(0, k.count - tailBeats - 1)
        let kt = k[lo...].map { Double($0) }
        var s = [Double]()
        var r0 = [Double]()
        for i in 1..<kt.count {
            s.append(kt[i])
            r0.append((kt[i] - kt[i - 1]) / Double(fs) * 1000.0)
        }
        let r = BeatCleaning.repairCausal(rri: r0, sampleIndex: s)
        let cnt = r.count
        var limit = cnt - 1          // 最後の1拍は②で取り消されることがあるので保留
        if cnt > 0 && r[cnt - 1].isNaN {   // 補間待ちの異常拍の連続は、次の正常拍まで保留
            var ps = cnt - 1
            while ps > 0 && r[ps - 1].isNaN { ps -= 1 }
            limit = min(limit, ps)
        }
        if limit <= 0 { return }
        for i in 0..<limit {
            if Int(s[i]) <= committedSample { continue }
            committedSample = Int(s[i])
            if r[i].isNaN { continue }
            if var out = rir.beat(rtime: s[i] / Double(fs), rri: r[i]) {
                out.sampleIndex = Int(s[i])
                beats.append(out)
            }
        }
    }
}

/// パケット単位の入口。本体時刻から欠落を見つけて RealtimeECG に伝える
/// (Python版 realtime/session.py の _on_ecg と同じ手順)。
public final class EcgSession {
    public let ecg: RealtimeECG
    var lastDevTime: Double? = nil
    public private(set) var packets = 0
    public private(set) var lost = 0

    public init(ecg: RealtimeECG = RealtimeECG()) { self.ecg = ecg }

    public func onPacket(_ p: EcgPacket) {
        if let last = lastDevTime {
            var gap = p.seconds - last
            if gap < -43200 { gap += 86400.0 }     // 日付をまたいだとき
            if gap <= 0.01 { return }              // 重複
            let miss = Int((gap / 0.2).rounded(.toNearestOrEven)) - 1
            if miss > 0 {
                lost += miss
                ecg.gap(50 * miss)
            }
        }
        lastDevTime = p.seconds
        ecg.push(p.samples)
        packets += 1
    }
}
