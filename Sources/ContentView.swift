import SwiftUI

struct ContentView: View {
    @ObservedObject var relay: RelayClient
    @ObservedObject var ble: BLEManager
    @StateObject private var finder = PCFinder()
    @State private var host: String = UserDefaults.standard.string(forKey: "host") ?? ""

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
