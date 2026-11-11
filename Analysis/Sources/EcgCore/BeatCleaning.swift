import Foundation

/// R波検出の後始末(偽の拍の除去、異常なRRIの補正)。
/// Python版(20261110_viewer_realtime.py)の逐次処理(causal)の関数を書き写したもの。
public enum BeatCleaning {
    static let adcMax = 0x3FFF

    /// ①記録値が下限/上限に張り付いた区間と、その直後 margin 点を true にする(未来は見ない)。
    public static func clipDropoutMask(_ adc: [Double], margin: Int) -> [Bool] {
        let rail = adc.map { $0 <= 1 || $0 >= Double(adcMax - 1) }
        if !rail.contains(true) || margin <= 0 { return rail }
        var out = [Bool](repeating: false, count: rail.count)
        var lastRail = -1 - margin - 1
        for i in 0..<rail.count {
            if rail[i] { lastRail = i }
            out[i] = (i - lastRail) <= margin
        }
        return out
    }

    /// ②直前の拍との間隔が短すぎる偽ピークを除く。
    /// 条件: 間隔が minRRSec(既定 60/230 = 約0.26秒)未満、または 過去の間隔の指数移動平均の 0.55倍 未満。
    /// 振幅の小さい方を除く。
    public static func sanitizeCausal(_ pk: [Int], amp: [Int: Double], fs: Int, maxRemoved: Int,
                                      emaAlpha: Double = 0.15,
                                      minRRSec: Double = 60.0 / RiRConst.maxHR) -> [Int] {
        var kept = [pk[0]]
        var ema: Double? = nil
        var removed = 0
        for p0 in pk.dropFirst() {
            var p: Int? = p0
            var rrNew = 0.0
            while true {
                rrNew = Double(p0 - kept[kept.count - 1]) / Double(fs)
                if ema == nil { ema = rrNew }
                let tooShort = rrNew < max(minRRSec, 0.55 * ema!)
                if !(tooShort && removed < maxRemoved && kept.count >= 2) { break }
                if amp[kept[kept.count - 1]]! < amp[p0]! {
                    kept.removeLast()
                    removed += 1
                    continue
                } else {
                    p = nil
                    removed += 1
                    break
                }
            }
            if let q = p {
                ema = (1 - emaAlpha) * ema! + emaAlpha * (Double(q - kept[kept.count - 1]) / Double(fs))
                kept.append(q)
            } else {
                ema = (1 - emaAlpha) * ema! + emaAlpha * rrNew
            }
        }
        return kept
    }

    /// 異常と判定した拍(fixed)を、直前・直後の正常拍のRRIから時刻基準の直線で埋める。
    /// 片側に正常拍が無い拍は nan。
    static func fillLinear(_ rri: [Double], t: [Double], fixed: [Bool]) -> [Double] {
        var out = rri
        let n = rri.count
        var j = 0
        while j < n {
            if !fixed[j] { j += 1; continue }
            var k = j
            while k < n && fixed[k] { k += 1 }
            let hasPrev = j > 0
            let hasNext = k < n
            if hasPrev && hasNext {
                let t0 = t[j - 1], t1 = t[k]
                let y0 = rri[j - 1], y1 = rri[k]
                for m in j..<k {
                    out[m] = t1 > t0 ? y0 + (y1 - y0) * (t[m] - t0) / (t1 - t0) : 0.5 * (y0 + y1)
                }
            } else {
                for m in j..<k { out[m] = Double.nan }
            }
            j = k
        }
        return out
    }

    /// ③異常なRRIの補正(逐次処理、線形補間)。過去 win 拍と自分だけを見て判定する。
    /// 判定: (a) 局所中央値との比が low 未満または high 超、
    ///       (b) 局所中央値との差が、周辺の拍のばらつき(下限 minScaleMs)の zThresh 倍超。
    public static func repairCausal(rri: [Double], sampleIndex: [Double], win: Int = 10,
                                    low: Double = 0.6, high: Double = 1.5,
                                    zThresh: Double = 6.0, minScaleMs: Double = 8.0) -> [Double] {
        let n = rri.count
        if n < win + 1 { return rri }
        var fixed = [Bool](repeating: false, count: n)
        for j in 0..<n {
            let a = max(0, j - win)
            let window = Array(rri[a...j])
            let med = median(window)
            let madScale = median(window.map { abs($0 - med) }) * 1.4826
            let scale = max(madScale, minScaleMs)
            let ratioBad = med > 0 && (rri[j] < low * med || rri[j] > high * med)
            let zBad = abs(rri[j] - med) > zThresh * scale
            if ratioBad || zBad { fixed[j] = true }
        }
        if !fixed.contains(true) { return rri }
        return fillLinear(rri, t: sampleIndex, fixed: fixed)
    }
}
