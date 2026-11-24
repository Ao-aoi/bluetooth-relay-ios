import SwiftUI

/// 接続タブ: 心電計との接続と、PCへの送信。
struct ConnectionTab: View {
    @ObservedObject var relay: RelayClient
    @ObservedObject var ble: BLEManager
    @ObservedObject var model: AnalysisModel
    @ObservedObject var mirror: MirrorClient
    @ObservedObject var finder: PCFinder
    @State private var manual = false
    @AppStorage("showWave") private var showWave = true
    @State private var host: String = UserDefaults.standard.string(forKey: "host") ?? ""

    var body: some View {
        Form {
            Section("心電計") {
                Button(ble.scanning ? "切断" : "心電計を探して接続") {
                    ble.scanning ? ble.stop() : ble.start()
                }
                Row("心電計", value: ble.deviceName.isEmpty ? "--" : ble.deviceName)
                Row("製造番号", value: ble.serial.isEmpty ? "--" : ble.serial)
                Text(ble.status)
                DisclosureGroup("心電図", isExpanded: $showWave) {
                    WaveView(store: model.waveStore, length: AnalysisModel.waveLength)
                }
                Row("心電図の受信パケット数", value: "\(ble.counts[0x01] ?? 0)")
                Row("心電図の欠落パケット数", value: "\(model.lostPackets)")
                Row("ジャイロセンサーの受信パケット数", value: "\(ble.counts[0x02] ?? 0)")
                Row("イベントの受信パケット数", value: "\(ble.counts[0x03] ?? 0)")
            }
            Section("PC") {
                Button("PCを探す") { finder.search() }
                ForEach(finder.pcs) { pc in
                    Button { connect(pc.ip) } label: {
                        Row(pc.name, value: pc.ip == host && relay.connected ? "接続中" : pc.ip)
                    }
                }
                DisclosureGroup("IPアドレスを入力", isExpanded: $manual) {
                    TextField("例 192.168.0.12", text: $host)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("接続") { connect(host) }.disabled(host.isEmpty)
                }
                Button(relay.running ? "PCへの送信を止める" : "PCへの送信を始める") {
                    if relay.running { relay.stop() } else {
                        UserDefaults.standard.set(host, forKey: "host")
                        relay.start(host: host)
                    }
                }
                Row("PCとの接続", value: relay.connected ? "接続中(暗号化)" : "未接続")
                if relay.mismatch { Text("PCの確認コードが前回と違うため、接続を止めています").foregroundColor(.red) }
                Row("未送信パケット数", value: "\(relay.bufferedCount)")
                Row("PCへ送った数", value: "\(relay.sentCount)")
            }
            Section("PCに解析結果を表示") {
                Button(mirror.running ? "表示停止" : "表示開始") {
                    mirror.running ? mirror.stop() : mirror.start(host: host)
                }
                .disabled(!mirror.running && host.isEmpty)
                Row("PCとの接続", value: mirror.connected ? "接続中(暗号化)" : "未接続")
                if mirror.mismatch { Text("PCの確認コードが前回と違うため、接続を止めています").foregroundColor(.red) }
            }
        }
        .onReceive(finder.$pcs) { pcs in
            if host.isEmpty, let p = pcs.first { host = p.ip }
        }
        .alert(item: Binding(get: { relay.pending ?? mirror.pending }, set: { if $0 == nil { relay.pending = nil; mirror.pending = nil } })) { p in
            Alert(title: Text("確認コード \(p.code)"),
                  message: Text("PCの画面のコードと同じなら「信頼する」を押してください。違う場合は別のPCです。"),
                  primaryButton: .default(Text("信頼する")) {
                      relay.trust(p)
                      mirror.trust(p)
                  },
                  secondaryButton: .cancel(Text("やめる")) {
                      if TLSPin.pinned(p.host) == nil { relay.stop(); mirror.stop() }
                  })
        }
    }

    /// 送信と解析結果の表示を同時に始める。
    private func connect(_ ip: String) {
        host = ip
        UserDefaults.standard.set(ip, forKey: "host")
        relay.stop(); mirror.stop()
        relay.start(host: ip)
        mirror.start(host: ip)
    }
}
