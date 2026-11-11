import Foundation

/// 心電計の心電パケット(105バイト)を読む。
/// 先頭4バイト: 本体時刻 [時][分][秒][1/256秒]、続く100バイト: 50サンプル(uint16、リトルエンディアン)。
public struct EcgPacket {
    public let seconds: Double     // 0時からの経過秒
    public let samples: [Int]

    public init?(_ d: [UInt8]) {
        guard d.count >= 104 else { return nil }
        seconds = Double(d[0]) * 3600 + Double(d[1]) * 60 + Double(d[2]) + Double(d[3]) / 256
        samples = (0..<50).map { i in Int(d[4 + 2*i]) | (Int(d[5 + 2*i]) << 8) }
    }
}
