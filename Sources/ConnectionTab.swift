import SwiftUI

/// 接続タブ: 心電計との接続と、PCへの送信。
struct ConnectionTab: View {
    @ObservedObject var relay: RelayClient
    @ObservedObject var ble: BLEManager
    @ObservedObject var model: AnalysisModel
    @ObservedObject var mirror: MirrorClient
    @ObservedObject var finder: PCFinder
    @State private var askMirror = false
    @AppStorage("showWave") private var showWave = true
    @State private var host: String = UserDefaults.standard.string(forKey: "host") ?? ""

    var body: some View {
        Form {
            Section("心電計") {
                Button(ble.scanning ? "切断" : "心電計を探して接続") {
                    ble.scanning ? ble.stop() : ble.start()
                }
                LabeledContent("心電計", value: ble.deviceName.isEmpty ? "--" : ble.deviceName)
                LabeledContent("製造番号", value: ble.serial.isEmpty ? "--" : ble.serial)
                Text(ble.status)
                DisclosureGroup("心電図", isExpanded: $showWave) {
                    WaveView(store: model.waveStore, length: AnalysisModel.waveLength)
                }
                LabeledContent("心電図の受信パケット数", value: "\(ble.counts[0x01] ?? 0)")
                LabeledContent("心電図の欠落パケット数", value: "\(model.lostPackets)")
                LabeledContent("ジャイロセンサーの受信パケット数", value: "\(ble.counts[0x02] ?? 0)")
                LabeledContent("イベントの受信パケット数", value: "\(ble.counts[0x03] ?? 0)")
            }
            Section("PC") {
                TextField("PCのIPアドレス(例 192.168.0.12)", text: $host)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("PCを探す") { finder.search() }
                ForEach(finder.pcs) { pc in
                    Button {
                        host = pc.ip
                        UserDefaults.standard.set(pc.ip, forKey: "host")
                        askMirror = true
                    } label: {
                        LabeledContent(pc.name, value: pc.ip)
                    }
                }
                Button(relay.running ? "PCへの送信を止める" : "PCへの送信を始める") {
                    if relay.running { relay.stop() } else {
                        UserDefaults.standard.set(host, forKey: "host")
                        relay.start(host: host)
                    }
                }
                LabeledContent("PCとの接続", value: relay.connected ? "接続中" : "未接続")
                LabeledContent("未送信パケット数", value: "\(relay.bufferedCount)")
                LabeledContent("PCへ送った数", value: "\(relay.sentCount)")
            }
            Section("PCに解析結果を表示") {
                Button(mirror.running ? "表示停止" : "表示開始") {
                    mirror.running ? mirror.stop() : mirror.start(host: host)
                }
                .disabled(!mirror.running && host.isEmpty)
                LabeledContent("PCとの接続", value: mirror.connected ? "接続中" : "未接続")
            }
        }
        .onReceive(finder.$pcs) { pcs in
            if host.isEmpty, let p = pcs.first { host = p.ip }
        }
        .alert("このPCに解析結果を表示しますか", isPresented: $askMirror) {
            Button("はい") { mirror.start(host: host) }
            Button("いいえ", role: .cancel) {}
        }
    }
}
