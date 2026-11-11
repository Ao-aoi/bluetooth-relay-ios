import SwiftUI

@main
struct KokologRelayApp: App {
    @StateObject private var relay: RelayClient
    @StateObject private var ble: BLEManager

    init() {
        let r = RelayClient()
        _relay = StateObject(wrappedValue: r)
        _ble = StateObject(wrappedValue: BLEManager(relay: r))
    }

    var body: some Scene {
        WindowGroup { ContentView(relay: relay, ble: ble) }
    }
}
