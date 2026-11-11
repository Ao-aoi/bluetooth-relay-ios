import Foundation

/// 中央値(要素が偶数個のときは中央2つの平均)。空の配列には使わないこと。
public func median(_ v: [Double]) -> Double {
    let s = v.sorted()
    let n = s.count
    if n % 2 == 1 { return s[n / 2] }
    return (s[n / 2 - 1] + s[n / 2]) / 2
}

/// 5〜25Hzの帯域通過フィルタ(バターワース3次、サンプリング250Hz)。
/// 係数は Python の scipy.signal.butter(3, [5/125, 25/125], btype="band", output="sos") の値。
public enum BandPass {
    // 各行: [b0, b1, b2, a1, a2](a0 は 1)
    static let sos: [[Double]] = [
        [0.010182576736436931, 0.020365153472873862, 0.010182576736436931, -1.5276383342122288, 0.5913983513994712],
        [1.0, 0.0, -1.0, -1.3805991856812434, 0.6709398694021094],
        [1.0, -2.0, 1.0, -1.895080792170117, 0.9118007928452695],
    ]
    // scipy.signal.sosfilt_zi(sos) の値(フィルタの初期状態)
    static let zi: [[Double]] = [
        [0.6286238217332516, -0.3676064741819706],
        [-0.6388063984696887, -0.6388063984696887],
        [0.0, 0.0],
    ]
    static let padlen = 21

    /// 前から1回フィルタを掛ける。scale は初期状態に掛ける値。
    static func sosfilt(_ x: [Double], scale: Double) -> [Double] {
        var z = zi.map { [$0[0] * scale, $0[1] * scale] }
        var out = [Double](repeating: 0, count: x.count)
        for n in 0..<x.count {
            var cur = x[n]
            for s in 0..<sos.count {
                let c = sos[s]
                let y = c[0] * cur + z[s][0]
                z[s][0] = c[1] * cur - c[3] * y + z[s][1]
                z[s][1] = c[2] * cur - c[4] * y
                cur = y
            }
            out[n] = cur
        }
        return out
    }

    /// 前後から1回ずつ掛けて、波形の時間ずれを無くす(scipy.signal.sosfiltfilt と同じ手順)。
    /// x の長さは padlen より大きいこと。
    public static func filtfilt(_ x: [Double]) -> [Double] {
        let n = x.count
        precondition(n > padlen)
        // 両端を点対称に延長する
        var ext = [Double]()
        ext.reserveCapacity(n + 2 * padlen)
        for i in stride(from: padlen, to: 0, by: -1) { ext.append(2 * x[0] - x[i]) }
        ext.append(contentsOf: x)
        for i in 1...padlen { ext.append(2 * x[n - 1] - x[n - 1 - i]) }

        var y = sosfilt(ext, scale: ext[0])
        y.reverse()
        y = sosfilt(y, scale: y[0])
        y.reverse()
        return Array(y[padlen..<(padlen + n)])
    }
}

/// 山(ピーク)を探す。scipy.signal.find_peaks(x, distance=, prominence=) と同じ手順。
/// 返り値はピークの位置(番号)。
public func findPeaks(_ x: [Double], distance: Int, prominence: Double) -> [Int] {
    let n = x.count
    // 1) 極大点(平らな頂上は中央)
    var peaks = [Int]()
    var i = 1
    let iMax = n - 1
    while i < iMax {
        if x[i - 1] < x[i] {
            var iAhead = i + 1
            while iAhead < iMax && x[iAhead] == x[i] { iAhead += 1 }
            if x[iAhead] < x[i] {
                let left = i
                let right = iAhead - 1
                peaks.append((left + right) / 2)
                i = iAhead
            }
        }
        i += 1
    }
    if peaks.isEmpty { return peaks }

    // 2) 近すぎるピークは、高い方を残す
    var keep = [Bool](repeating: true, count: peaks.count)
    let order = (0..<peaks.count).sorted { a, b in
        x[peaks[a]] != x[peaks[b]] ? x[peaks[a]] < x[peaks[b]] : a < b
    }
    for q in stride(from: peaks.count - 1, through: 0, by: -1) {
        let j = order[q]
        if !keep[j] { continue }
        var k = j - 1
        while k >= 0 && peaks[j] - peaks[k] < distance {
            keep[k] = false
            k -= 1
        }
        k = j + 1
        while k < peaks.count && peaks[k] - peaks[j] < distance {
            keep[k] = false
            k += 1
        }
    }
    peaks = zip(peaks, keep).filter { $0.1 }.map { $0.0 }

    // 3) 周りからの突き出し(prominence)が小さいものを除く
    var result = [Int]()
    for p in peaks {
        var leftMin = x[p]
        var k = p
        while k >= 0 && x[k] <= x[p] {
            if x[k] < leftMin { leftMin = x[k] }
            k -= 1
        }
        var rightMin = x[p]
        k = p
        while k < n && x[k] <= x[p] {
            if x[k] < rightMin { rightMin = x[k] }
            k += 1
        }
        if x[p] - max(leftMin, rightMin) >= prominence { result.append(p) }
    }
    return result
}
