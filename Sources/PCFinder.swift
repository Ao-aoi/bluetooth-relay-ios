import Foundation
import Network

/// 同じWi-Fi内で pc_receiver.py を自動で探し、PCのIPアドレスを見つける(Bonjour)。
final class PCFinder: ObservableObject {
    @Published var found: String? = nil
    private var browser: NWBrowser?
    private var conn: NWConnection?

    func search() {
        browser?.cancel()
        let b = NWBrowser(for: .bonjour(type: "_btrelay._tcp", domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self, let r = results.first else { return }
            self.resolve(r.endpoint)
        }
        b.start(queue: .main)
        browser = b
    }

    /// 見つけたPCに一度つないで、相手のIPv4アドレスを取り出す。
    private func resolve(_ ep: NWEndpoint) {
        let p = NWParameters.tcp
        if let ip = p.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
        let c = NWConnection(to: ep, using: p)
        c.stateUpdateHandler = { [weak self] st in
            guard let self else { return }
            if case .ready = st, case .hostPort(let host, _)? = c.currentPath?.remoteEndpoint {
                var s = "\(host)"
                if let i = s.firstIndex(of: "%") { s = String(s[..<i]) }
                self.found = s
                self.browser?.cancel()
                c.cancel()
            }
        }
        c.start(queue: .main)
        conn = c
    }
}
