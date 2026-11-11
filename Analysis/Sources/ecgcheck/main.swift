import Foundation
import EcgCore

// 使い方: swift run ecgcheck <入力.ecg> <出力.csv>
// .ecg(16bit、250Hz)を0.2秒(50点)ずつ解析に流し、拍ごとの結果をCSVに書く。
// Python版(kokolog_test の realtime/export_beats.py)の出力と比べるためのプログラム。

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("使い方: swift run ecgcheck <入力.ecg> <出力.csv>")
    exit(1)
}
guard let data = FileManager.default.contents(atPath: args[1]) else {
    print("読めません:", args[1])
    exit(1)
}
let bytes = [UInt8](data)
let total = bytes.count / 2
let ecg = RealtimeECG()
let start = Date()
var pos = 0
while pos + 50 <= total {
    var chunk = [Int]()
    chunk.reserveCapacity(50)
    for i in pos..<(pos + 50) { chunk.append(Int(bytes[2 * i]) | (Int(bytes[2 * i + 1]) << 8)) }
    ecg.push(chunk)
    pos += 50
}
let sec = Date().timeIntervalSince(start)

func fmt(_ v: Double?) -> String { v == nil ? "" : String(v!) }
var lines = ["time_s,sample_index,RRI_ms,HR_bpm,RiR,sumrir_per_span,La"]
for b in ecg.beats {
    lines.append("\(b.timeS),\(b.sampleIndex),\(b.rriMs),\(b.hrBpm),\(fmt(b.rir)),\(fmt(b.sumrirPerSpan)),\(fmt(b.La))")
}
do {
    try (lines.joined(separator: "\n") + "\n").write(toFile: args[2], atomically: true, encoding: .utf8)
} catch {
    print("書けません:", args[2])
    exit(1)
}
print("記録の長さ: \(Double(pos) / 250.0) 秒、拍の数: \(ecg.beats.count)、計算時間: \(sec) 秒")
