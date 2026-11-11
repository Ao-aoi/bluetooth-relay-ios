import SwiftUI

@main
struct BluetoothRelayApp: App {
    @StateObject private var relay: RelayClient
    @StateObject private var ble: BLEManager
    @StateObject private var model: AnalysisModel

    init() {
        let r = RelayClient()
        let m = AnalysisModel()
        _relay = StateObject(wrappedValue: r)
        _model = StateObject(wrappedValue: m)
        _ble = StateObject(wrappedValue: BLEManager(relay: r, analysis: m))
    }

    var body: some Scene {
        WindowGroup { ContentView(relay: relay, ble: ble, model: model) }
    }
}
