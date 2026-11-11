import Foundation

/// 状態(安静 / 軽い動き / 運動)の推定。Python版 realtime/activity.py と同じ規則・同じ閾値
/// (Python版では「安静」を「静止」と呼んでいる)。
/// 閾値は仮の値。変えるときは Python版と一緒に直す。
public enum ActivityConst {
    public static let gyroHz = 30.0            // ジャイロのサンプル数/秒(1パケット6サンプル × 5パケット/秒)
    public static let motionWindowSec = 2.0    // 動きの大きさ M を求める窓
    public static let motionSmoothSec = 6.0    // M の中央値をとる期間
    public static let tLight = 250.0           // M がこれ以上で「動いている」
    public static let tExercise = 1000.0       // M がこれ以上で「運動」
    public static let hrRest = 60.0            // 安静時心拍
    public static let hrHighDelta = 40.0       // 安静時+これ以上(100bpm)を「心拍が高い」とみなす
    public static let hrWindowSec = 30.0       // 心拍は直近30秒の中央値
    public static let hrMinBeats = 10          // これ未満の拍数なら心拍は「不明」
    public static let hrValidLow = 40.0        // 中央値がこの範囲の外なら雑音とみなす
    public static let hrValidHigh = 200.0
    public static let hrRRDispersionMax = 0.20 // RRIのばらつき(MAD/中央値)がこれを超えたら雑音とみなす
    public static let gyroTimeoutSec = 3.0     // ジャイロがこの秒数届かなければ「不明」
    public static let holdSec = 3.0            // 新しい状態がこの秒数続いてから切り替える
}

public enum ActivityState: String {
    case rest = "安静"
    case light = "軽い動き"
    case exercise = "運動"
    case unknown = "不明"
}

public final class ActivityEstimator {
    var g = [(t: Double, x: Double, y: Double, z: Double)]()   // ジャイロ(直近120秒)
    var mHist = [(t: Double, m: Double)]()                     // 動きの大きさ M の履歴
    public private(set) var state = ActivityState.unknown
    public private(set) var note = "ジャイロ待ち"
    var cand: ActivityState? = nil
    var candSince = 0.0
    public private(set) var motion = Double.nan
    public private(set) var hr = Double.nan
    public private(set) var hrOk = false

    public init() {}

    /// ジャイロの18個(6サンプル×3軸)を足す。先頭6個がx、次の6個がy、最後の6個がzと仮定。
    public func addGyro(time: Double, values v: [Int]) {
        guard v.count >= 18 else { return }
        for i in 0..<6 {
            g.append((time + Double(i - 5) / ActivityConst.gyroHz, Double(v[i]), Double(v[6 + i]), Double(v[12 + i])))
        }
        let cap = Int(ActivityConst.gyroHz * 120)
        if g.count > cap { g.removeFirst(g.count - cap) }
    }

    /// 動きの大きさ M: 直近2秒の「3軸それぞれの標準偏差の二乗和の平方根」。
    func motionNow(_ now: Double) -> Double {
        let w = g.filter { now - $0.t <= ActivityConst.motionWindowSec }
        if Double(w.count) < ActivityConst.gyroHz * ActivityConst.motionWindowSec * 0.6 { return .nan }
        let n = Double(w.count)
        func variance(_ a: [Double]) -> Double {
            let mean = a.reduce(0, +) / n
            return a.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n
        }
        return (variance(w.map { $0.x }) + variance(w.map { $0.y }) + variance(w.map { $0.z })).squareRoot()
    }

    /// 直近30秒の拍から心拍(中央値)を求める。雑音らしければ ok が false。
    public func hrEstimate(_ beats: [BeatResult], nowS: Double) -> (hr: Double, ok: Bool) {
        let r = beats.suffix(120).filter { nowS - $0.timeS <= ActivityConst.hrWindowSec }
        if r.count < ActivityConst.hrMinBeats { return (.nan, false) }
        let hr = median(r.map { $0.hrBpm })
        let rr = r.map { $0.rriMs }
        let med = median(rr)
        let disp = med > 0 ? median(rr.map { abs($0 - med) }) / med : 9.0
        let ok = ActivityConst.hrValidLow <= hr && hr <= ActivityConst.hrValidHigh
            && disp <= ActivityConst.hrRRDispersionMax
        return (hr, ok)
    }

    /// 状態を更新して返す。time: 心電計の本体時刻[秒]、nowS: 心電図の経過秒。
    @discardableResult
    public func update(time: Double, beats: [BeatResult], nowS: Double, signalBad: Bool = false) -> ActivityState {
        guard let last = g.last, time - last.t <= ActivityConst.gyroTimeoutSec else {
            state = .unknown
            note = "ジャイロが届いていません"
            return state
        }
        let m = motionNow(time)
        if !m.isNaN {
            mHist.append((time, m))
            let cap = Int(ActivityConst.gyroHz * 2)
            if mHist.count > cap { mHist.removeFirst(mHist.count - cap) }
        }
        let ms = mHist.filter { time - $0.t <= ActivityConst.motionSmoothSec }.map { $0.m }
        motion = ms.isEmpty ? .nan : median(ms)
        (hr, hrOk) = hrEstimate(beats, nowS: nowS)
        if signalBad { hrOk = false }      // 信号品質が「不良」のときは心拍を信用しない
        if motion.isNaN { return state }
        let high = hrOk && hr >= ActivityConst.hrRest + ActivityConst.hrHighDelta
        var s: ActivityState
        var n: String
        if motion >= ActivityConst.tExercise {
            s = .exercise; n = "動きが大きい"
        } else if motion >= ActivityConst.tLight {
            if high { s = .exercise; n = "動き+心拍が高い" } else { s = .light; n = "動きは中程度" }
        } else {
            s = .rest
            n = high ? "動きは小さいが心拍が高め" : "動きが小さい"
        }
        if !hrOk { n += "(心拍は使わずジャイロだけで判定)" }
        // 新しい状態が holdSec 続いたら切り替える
        if s != state {
            if cand != s { cand = s; candSince = time }
            if time - candSince >= ActivityConst.holdSec || state == .unknown { state = s }
        } else {
            cand = nil
        }
        note = n
        return state
    }
}
