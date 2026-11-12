import SwiftUI

/// 画面全体。下のタブで 解析 / 接続 / 履歴 / 設定 を切り替える。
struct ContentView: View {
    let relay: RelayClient
    let ble: BLEManager
    let model: AnalysisModel
    @StateObject private var finder = PCFinder()
    @AppStorage("autoScanDevice") private var autoScanDevice = false
    @AppStorage("autoFindPC") private var autoFindPC = false

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
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true   // 使っている間は画面を消さない
            if autoFindPC { finder.search() }
            if autoScanDevice { ble.start() }
        }
    }
}
