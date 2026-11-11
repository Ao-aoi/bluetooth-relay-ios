import Foundation

// RiR / ΣRiR / La を計算する解析部。
// 基準プログラム Uef190901 (Copyright (c) 2019 Yoshihito Sawaguchi) を、
// Python版(20260901_viewer.py)の UnevenFilter / MovAveFilter / FatigueEstimator から
// 式を変えずにSwiftへ書き写したもの。式を変更しないこと。

public enum RiRConst {
    public static let filtOrd = 4
    public static let maxHR: Double = 230      // 220 + 10
    public static let ngSpan: Double = 0.8

    public static let lfPoles = [Complex(-0.363526, 0.745429), Complex(-0.363526, -0.745429),
                                 Complex(-0.125191, 0.256712), Complex(-0.125191, -0.256712)]
    public static let lfGains = [Complex(0.085964, -0.383970), Complex(0.085964, 0.383970),
                                 Complex(-0.085964, 0.104747), Complex(-0.085964, -0.104747)]
    public static let hfPoles = [Complex(-0.754108, 2.107200), Complex(-0.754108, -2.107200),
                                 Complex(-0.356612, 0.996479), Complex(-0.356612, -0.996479)]
    public static let hfGains = [Complex(0.170497, -0.775944), Complex(0.170497, 0.775944),
                                 Complex(-0.170497, 0.334776), Complex(-0.170497, -0.334776)]
    public static let vfPoles = [Complex(-1.777153, 5.331460), Complex(-1.777153, -5.331460),
                                 Complex(-0.888577, 2.665730), Complex(-0.888577, -2.665730)]
    public static let vfGains = [Complex(0.390107, -1.820498), Complex(0.390107, 1.820498),
                                 Complex(-0.390107, 0.845231), Complex(-0.390107, -0.845231)]
}

/// 不等間隔のRRI系列にそのまま掛けられる帯域フィルタ(複素極のフィルタバンク)。
public final class UnevenFilter {
    let poles: [Complex]
    let gains: [Complex]
    var prevU: Double
    var prevT: Double
    public private(set) var y: Double = 0.0
    let ngSpan: Double
    var x: [Complex]
    var g0: [Complex]

    public init(poles: [Complex], gains: [Complex], t0: Double, u0: Double, ngSpan: Double = RiRConst.ngSpan) {
        self.poles = poles
        self.gains = gains
        self.prevU = u0
        self.prevT = t0
        self.ngSpan = ngSpan
        var g0 = [Complex](repeating: .zero, count: RiRConst.filtOrd)
        var x = [Complex](repeating: .zero, count: RiRConst.filtOrd)
        for k in 0..<RiRConst.filtOrd {
            g0[k] = -(gains[k] / poles[k])
            x[k] = g0[k] * u0
        }
        self.g0 = g0
        self.x = x
    }

    public func filter(t: Double, u: Double) {
        let p = poles
        let g = gains
        let T = t - prevT
        let one = Complex(1, 0)

        if (T - (u / 1000.0)) > ngSpan {
            // 欠測(長い無拍区間)とみなす
            for k in 0..<RiRConst.filtOrd {
                let Ad = Complex.exp(p[k] * T)
                let Bd = (one - Ad) * g0[k]
                let scaled: Complex = Ad * x[k] / prevU
                x[k] = (scaled + Bd) * u
            }
            y = -1.0
        } else {
            let du = u - prevU
            for k in 0..<RiRConst.filtOrd {
                let Ad = Complex.exp(p[k] * T)
                let Bd = (one - Ad) * g0[k]
                let term1: Complex = Ad * x[k]
                let term2: Complex = Bd * prevU
                let term3: Complex = (Bd / T - g[k]) / p[k] * du
                x[k] = term1 + term2 + term3
            }
            var s = Complex.zero
            for k in 0..<RiRConst.filtOrd { s = s + x[k] }
            y = s.re * s.re
        }
        prevT = t
        prevU = u
    }
}

/// 帯域パワーの移動平均(int_span 秒)。有効な拍が valid_span 秒ぶん溜まるまで power は -1。
public final class MovAveFilter {
    let intSpan: Double
    let validSpan: Double
    let buflen: Int
    var buf: [[Double]]
    var idx = 1
    var kmin = 0
    var itgr: Double
    public private(set) var sumt: Double
    public private(set) var power: Double = -1.0

    public init(t0: Double, y0: Double, rri0: Double, intSpan: Double, validSpan: Double,
                maxHR: Double = RiRConst.maxHR) {
        self.intSpan = intSpan
        self.validSpan = validSpan
        let len = Int(intSpan * maxHR / 20)
        self.buflen = len
        var b = [[Double]](repeating: [0.0, 0.0, 0.0], count: len)
        b[0] = [t0, y0, rri0]
        self.buf = b
        self.itgr = y0 * rri0
        self.sumt = rri0
    }

    public func filter(t: Double, y: Double, rri: Double) {
        buf[idx] = [t, y, rri]
        itgr += (y * rri)
        sumt += rri
        var span = t - buf[kmin][0]

        while span > intSpan {
            let newkmin = (kmin + 1) % buflen
            let deltaT = buf[newkmin][0] - buf[kmin][0]
            itgr -= buf[kmin][1] * buf[kmin][2]
            sumt -= buf[kmin][2]
            span -= deltaT
            kmin = newkmin
        }

        idx = (idx + 1) % buflen

        if sumt > (validSpan * 1000) {
            power = itgr / sumt
        } else {
            power = -1.0
        }
    }
}

/// ΣRiR と疲労度 La の推定。
public final class FatigueEstimator {
    let hr0: Double
    let sumrirSpan: Double
    let rbuflen: Int
    public private(set) var tRecv = 0.0
    var buf: [[Double]]
    var idx = 0
    var kmin = 0
    public private(set) var sumrir = 0.0
    public private(set) var dHR = 0.0
    public private(set) var La = 0.0
    var sumrdh = 0.0
    var prevT = -1.0
    var prevU = 0.0
    var seeded = false

    public init(hr0: Double, sumrirSpan: Double, maxHR: Double = RiRConst.maxHR) {
        self.hr0 = hr0
        self.sumrirSpan = sumrirSpan
        let len = Int(sumrirSpan * maxHR / 20)
        self.rbuflen = len
        self.buf = [[Double]](repeating: [0.0, 0.0], count: len)
    }

    public func estimate(t: Double, y: Double, rri: Double) {
        buf[idx] = [t, y]

        if seeded {
            let prevIdx = (idx - 1 + rbuflen) % rbuflen
            let deltaT = t - buf[prevIdx][0]
            sumrir += (buf[prevIdx][1] + y) * deltaT / 2.0
        } else {
            seeded = true
        }

        idx = (idx + 1) % rbuflen
        var span = t - buf[kmin][0]

        while span > sumrirSpan {
            let newkmin = (kmin + 1) % rbuflen
            let deltaT = buf[newkmin][0] - buf[kmin][0]

            if (span - deltaT) < sumrirSpan {
                let deltaY = buf[newkmin][1] - buf[kmin][1]
                let newDt = (span - sumrirSpan)
                let newy = (deltaY / deltaT) * newDt + buf[kmin][1]
                sumrir -= (buf[kmin][1] + newy) * newDt / 2.0
                buf[kmin] = [(t - sumrirSpan), newy]
                break
            }

            sumrir -= (buf[kmin][1] + buf[newkmin][1]) * deltaT / 2.0
            span -= deltaT
            kmin = newkmin
        }

        dHR = ((60000 / rri) - hr0)

        if y < 0.3 {
            prevT = -1.0
        } else {
            let rdh = dHR * y
            if prevT > 0 {
                sumrdh += (prevU + rdh) * (t - prevT) / 2
                La = 18 - 14 * exp(-sumrdh / 50000)
                if La > 4.0 {
                    tRecv = 62.2 - 41.2 * sqrt(log(15.6 / (La - 2.4)))
                }
            }
            prevT = t
            prevU = rdh
        }
    }
}

/// 1拍ぶんの解析結果。値が出ていない項目は nil。
public struct BeatResult {
    public var timeS: Double
    public var sampleIndex: Int = 0
    public var rriMs: Double
    public var hrBpm: Double
    public var rir: Double?
    public var sumrir: Double?
    public var sumrirPerSpan: Double?
    public var dHR: Double
    public var La: Double?
}

/// 1拍ずつ与えて RiR を計算する(Python版 realtime/pipeline.py の RealtimeRiR と同じ手順)。
public final class RealtimeRiR {
    enum State { case waitForFirstR, waitForFilterOutput, waitForFirstRir, ok }

    let hr0: Double
    public let validSpan: Double
    let intSpan: Double
    let sumrirSpan: Double
    let ngSpan: Double
    let maxHR: Double
    var state = State.waitForFirstR
    public private(set) var reseeds = 0
    var ll: UnevenFilter!, hh: UnevenFilter!, vv: UnevenFilter!
    var lf: MovAveFilter!, hf: MovAveFilter!, vf: MovAveFilter!
    var fe: FatigueEstimator!

    public init(hr0: Double = 60.0, validSpan: Double = 120.0, intSpan: Double = 180.0,
                sumrirSpan: Double = 120.0, ngSpan: Double = RiRConst.ngSpan, maxHR: Double = RiRConst.maxHR) {
        self.hr0 = hr0
        self.validSpan = validSpan
        self.intSpan = intSpan
        self.sumrirSpan = sumrirSpan
        self.ngSpan = ngSpan
        self.maxHR = maxHR
    }

    /// 確定した1拍(R波時刻[秒]・RRI[ms])を与える。出力できる拍なら結果、まだなら nil。
    public func beat(rtime: Double, rri: Double) -> BeatResult? {
        if state == .waitForFirstR {
            ll = UnevenFilter(poles: RiRConst.lfPoles, gains: RiRConst.lfGains, t0: rtime, u0: rri, ngSpan: ngSpan)
            hh = UnevenFilter(poles: RiRConst.hfPoles, gains: RiRConst.hfGains, t0: rtime, u0: rri, ngSpan: ngSpan)
            vv = UnevenFilter(poles: RiRConst.vfPoles, gains: RiRConst.vfGains, t0: rtime, u0: rri, ngSpan: ngSpan)
            state = .waitForFilterOutput
            return nil
        }
        ll.filter(t: rtime, u: rri); hh.filter(t: rtime, u: rri); vv.filter(t: rtime, u: rri)
        if ll.y < 0 {
            reseeds += 1
            return nil
        }
        if state == .waitForFilterOutput {
            lf = MovAveFilter(t0: rtime, y0: ll.y, rri0: rri, intSpan: intSpan, validSpan: validSpan, maxHR: maxHR)
            hf = MovAveFilter(t0: rtime, y0: hh.y, rri0: rri, intSpan: intSpan, validSpan: validSpan, maxHR: maxHR)
            vf = MovAveFilter(t0: rtime, y0: vv.y, rri0: rri, intSpan: intSpan, validSpan: validSpan, maxHR: maxHR)
            state = .waitForFirstRir
            return nil
        }
        lf.filter(t: rtime, y: ll.y, rri: rri); hf.filter(t: rtime, y: hh.y, rri: rri)
        vf.filter(t: rtime, y: vv.y, rri: rri)
        let dhr = rri > 0 ? ((60000.0 / rri) - hr0) : 0.0
        let powerValid = !(lf.power < 0 || hf.power < 0 || vf.power < 0)
        var out = BeatResult(timeS: rtime, rriMs: rri, hrBpm: rri > 0 ? 60000.0 / rri : 0,
                             rir: nil, sumrir: nil, sumrirPerSpan: nil, dHR: dhr, La: nil)
        if powerValid {
            let total = lf.power + hf.power + vf.power
            let rir = total != 0 ? vf.power / total : 0
            if state == .waitForFirstRir {
                fe = FatigueEstimator(hr0: hr0, sumrirSpan: sumrirSpan, maxHR: maxHR)
                state = .ok
            }
            fe.estimate(t: rtime, y: rir, rri: rri)
            out.rir = rir
            out.sumrir = fe.sumrir
            out.sumrirPerSpan = fe.sumrir / sumrirSpan
            out.La = fe.La
        }
        return out
    }

    /// 途切れずに有効な拍が続いた時間[秒]。validSpan に達すると RiR が出る。
    public func validSec() -> Double {
        if state == .waitForFirstR || state == .waitForFilterOutput { return 0.0 }
        return lf.sumt / 1000.0
    }
}
