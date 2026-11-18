import SwiftUI

/// 画面全体。下のタブで 解析 / 接続 / 履歴 / 設定 を切り替える。
struct ContentView: View {
    let relay: RelayClient
    let ble: BLEManager
    let model: AnalysisModel
    @StateObject private var finder = PCFinder()
    @AppStorage("autoScanDevice") private var autoScanDevice = false
    @AppStorage("autoFindPC") private var autoFindPC = false
    @AppStorage("appearance") private var appearance = 0   // 0=端末の設定に合わせる 1=ライト 2=ダーク

    var body: some View {
        TabView {
            AnalysisTab(model: model)
                .tabItem { Label("解析", systemImage: "chart.xyaxis.line") }
            ConnectionTab(relay: relay, ble: ble, model: model, mirror: model.mirror, finder: finder)
                .tabItem { Label("接続", systemImage: "antenna.radiowaves.left.and.right") }
            HistoryTab(model: model)
                .tabItem { Label("履歴", systemImage: "clock.arrow.circlepath") }
            SettingsTab(model: model)
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
        .preferredColorScheme(appearance == 1 ? .light : appearance == 2 ? .dark : nil)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true   // 使っている間は画面を消さない
            if autoFindPC { finder.search() }
            if autoScanDevice { ble.start() }
        }
    }
}
