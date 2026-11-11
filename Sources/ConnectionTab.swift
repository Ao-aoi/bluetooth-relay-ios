import SwiftUI

/// 接続タブ: 心電計との接続と、PCへの送信。
struct ConnectionTab: View {
    @ObservedObject var relay: RelayClient
    @ObservedObject var ble: BLEManager
    @ObservedObject var model: AnalysisModel
    @ObservedObject var finder: PCFinder
    @State private var host: String = UserDefaults.standard.string(forKey: "host") ?? ""

    var body: some View {
        Form {
            Section("心電計") {
                Button(ble.scanning ? "切断" : "心電計を探して接続") {
                    ble.scanning ? ble.stop() : ble.start()
                }
                Text(ble.status)
                WaveView(store: model.waveStore, length: AnalysisModel.waveLength)
                Text("▼ は検出したR波").font(.caption).foregroundColor(.secondary)
                LabeledContent("心電図", value: "\(ble.counts[0x01] ?? 0)")
                LabeledContent("動き", value: "\(ble.counts[0x02] ?? 0)")
                LabeledContent("5秒ごと", value: "\(ble.counts[0x03] ?? 0)")
                LabeledContent("届かなかったパケット", value: "\(model.lostPackets)")
            }
            Section("PC") {
                TextField("PCのIPアドレス(例 192.168.0.12)", text: $host)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("PCを探す") { finder.search() }
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
        }
        .onReceive(finder.$found) { ip in
            if let ip { host = ip }
        }
    }
}
