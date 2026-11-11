import Foundation

/// 複素数(Swiftの標準には無いので、必要な演算だけ用意する)。
public struct Complex {
    public var re: Double
    public var im: Double
    public init(_ re: Double, _ im: Double) { self.re = re; self.im = im }

    public static let zero = Complex(0, 0)

    public static func + (a: Complex, b: Complex) -> Complex { Complex(a.re + b.re, a.im + b.im) }
    public static func - (a: Complex, b: Complex) -> Complex { Complex(a.re - b.re, a.im - b.im) }
    public static func * (a: Complex, b: Complex) -> Complex {
        Complex(a.re * b.re - a.im * b.im, a.re * b.im + a.im * b.re)
    }
    public static func / (a: Complex, b: Complex) -> Complex {
        let d = b.re * b.re + b.im * b.im
        return Complex((a.re * b.re + a.im * b.im) / d, (a.im * b.re - a.re * b.im) / d)
    }
    public static func * (a: Complex, s: Double) -> Complex { Complex(a.re * s, a.im * s) }
    public static func / (a: Complex, s: Double) -> Complex { Complex(a.re / s, a.im / s) }
    public static prefix func - (a: Complex) -> Complex { Complex(-a.re, -a.im) }

    /// e の複素数乗
    public static func exp(_ z: Complex) -> Complex {
        let m = Foundation.exp(z.re)
        return Complex(m * cos(z.im), m * sin(z.im))
    }
}
