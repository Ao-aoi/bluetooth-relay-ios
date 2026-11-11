import Foundation
import EcgCore

// 動作確認: 作り物のパケットを1つ読んで表示する
var bytes: [UInt8] = [12, 34, 56, 128]
for i in 0..<50 { let v = 8192 + i; bytes += [UInt8(v & 0xff), UInt8(v >> 8)] }
bytes.append(0)
if let p = EcgPacket(bytes) {
    print("時刻(秒):", p.seconds)
    print("最初の5サンプル:", Array(p.samples.prefix(5)))
}
