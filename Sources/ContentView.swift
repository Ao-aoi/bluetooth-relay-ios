import SwiftUI

struct ContentView: View {
    @ObservedObject var relay: RelayClient
    @ObservedObject var ble: BLEManager
    @StateObject private var finder = PCFinder()
    @State private var host: String = UserDefaults.standard.string(forKey: "host") ?? ""

    /// RiRの表示。まだ出ていない間は、あと何秒ぶんの拍が必要かを出す。
    private var rirText: String {
        if let r = ble.rir { return String(format: "%.3f", r) }
        if ble.heartRate == nil { return "--" }
        return String(format: "準備中(%.0f / %.0f 秒)", min(ble.validSec, ble.validSpan), ble.validSpan)
    }

    /// 信号品質の表示。50Hz混入の振幅で 良好 / 注意 / 不良 を分ける。
    private var qualityText: String {
        guard let q = ble.quality else { return "--" }
        let label = ["良好", "注意", "不良"][q.level]
        return "\(label)(50Hz混入 \(Int(q.mains.rounded())))"
    }

    var body: some View {
        Form {
            Section("PC") {
                TextField("PCのIPアドレス(例 192.168.0.12)", text: $host)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("PCを自動で探す") { finder.search() }
                Button(relay.running ? "PCへの送信を止める" : "PCへの送信を始める") {
                    if relay.running { relay.stop() } else {
                        UserDefaults.standard.set(host, forKey: "host")
                        relay.start(host: host)
                    }
                }
                LabeledContent("PCとの接続", value: relay.connected ? "つながっています" : "つながっていません")
                LabeledContent("ためてある数", value: "\(relay.bufferedCount)")
                LabeledContent("PCへ送った数", value: "\(relay.sentCount)")
            }
            Section("心電計") {
                Button(ble.scanning ? "探すのを止める" : "心電計を探して接続") {
                    ble.scanning ? ble.stop() : ble.start()
                }
                Text(ble.status)
                WaveView(samples: ble.wave, length: 1250)
                LabeledContent("心電図", value: "\(ble.counts[0x01] ?? 0)")
                LabeledContent("動き", value: "\(ble.counts[0x02] ?? 0)")
                LabeledContent("5秒ごと", value: "\(ble.counts[0x03] ?? 0)")
            }
            Section("解析") {
                LabeledContent("心拍数", value: ble.heartRate.map { String(format: "%.0f bpm", $0) } ?? "--")
                LabeledContent("RiR", value: rirText)
                LabeledContent("信号品質", value: qualityText)
                LabeledContent("届かなかったパケット", value: "\(ble.lostPackets)")
                Button("解析をやり直す") { ble.resetAnalysis() }
            }
            Section {
                Text("使っている間は画面を点けたままにします。他の人の心電計に繋がないよう、近くの1台だけ電源を入れてください。")
                    .font(.footnote)
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            finder.search()   // 起動時に自動でPCを探す
        }
        .onReceive(finder.$found) { ip in
            if let ip { host = ip; UserDefaults.standard.set(ip, forKey: "host") }
        }
    }
}
