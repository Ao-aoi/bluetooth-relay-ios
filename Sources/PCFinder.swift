import Foundation
import Network

/// 見つけたPC。
struct FoundPC: Identifiable, Equatable {
    let ip: String
    let name: String
    var id: String { ip }
}

/// 同じWi-Fi内で、受信プログラムを動かしているPCを探す(Bonjour)。
final class PCFinder: ObservableObject {
    @Published var pcs: [FoundPC] = []
    private var browser: NWBrowser?
    private var conns: [NWConnection] = []
    private var seen = Set<String>()

    func search() {
        browser?.cancel()
        conns.forEach { $0.cancel() }
        conns = []
        seen = []
        pcs = []
        let b = NWBrowser(for: .bonjour(type: "_btrelay._tcp", domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            for r in results {
                let key = "\(r.endpoint)"
                if self.seen.contains(key) { continue }
                self.seen.insert(key)
                var name = key
                if case .service(let n, _, _, _) = r.endpoint { name = n }
                self.resolve(r.endpoint, name: name)
            }
        }
        b.start(queue: .main)
        browser = b
    }

    /// 見つけたPCに一度つないで、相手のIPv4アドレスを取り出す。
    private func resolve(_ ep: NWEndpoint, name: String) {
        let p = NWParameters.tcp
        if let ip = p.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
        let c = NWConnection(to: ep, using: p)
        c.stateUpdateHandler = { [weak self] st in
            guard let self else { return }
            if case .ready = st, case .hostPort(let host, _)? = c.currentPath?.remoteEndpoint {
                var s = "\(host)"
                if let i = s.firstIndex(of: "%") { s = String(s[..<i]) }
                if !self.pcs.contains(where: { $0.ip == s }) { self.pcs.append(FoundPC(ip: s, name: name)) }
                c.cancel()
            }
        }
        c.start(queue: .main)
        conns.append(c)
    }
}
