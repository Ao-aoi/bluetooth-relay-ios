import Foundation

/// 解析結果(心拍数・RiRなど)を、PCの pc_monitor.py へ WebSocket(ws://<PC>:9751)で送る。
/// 1秒に1回、JSONの文字メッセージを1つ送る。つながっていない間は送らない
/// (つながり直したときに、AnalysisModel が直近の拍をまとめて送り直す)。
final class MirrorClient: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    @Published var running = false
    @Published var connected = false
    @Published var host = ""

    static let port = 9751
    var onOpen: (() -> Void)?
    private var task: URLSessionWebSocketTask?
    private var session: URLSession!
    private var retry: Timer?

    override init() {
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    }

    func start(host: String) {
        stop()
        self.host = host
        running = true
        connect()
        retry = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self, self.running, !self.connected, self.task == nil else { return }
            self.connect()
        }
    }

    func stop() {
        running = false
        retry?.invalidate(); retry = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        connected = false
    }

    private func connect() {
        guard let url = URL(string: "ws://\(host):\(Self.port)") else { return }
        let t = session.webSocketTask(with: url)
        task = t
        t.resume()
        listen(t)
    }

    /// PCからは何も送ってこないが、切断に気づくために受信を待つ。
    private func listen(_ t: URLSessionWebSocketTask) {
        t.receive { [weak self] result in
            guard let self, t === self.task else { return }
            switch result {
            case .success: self.listen(t)
            case .failure: self.dropped()
            }
        }
    }

    private func dropped() {
        task = nil
        connected = false
    }

    func urlSession(_ s: URLSession, webSocketTask t: URLSessionWebSocketTask, didOpenWithProtocol p: String?) {
        guard t === task else { return }
        connected = true
        onOpen?()
    }

    func urlSession(_ s: URLSession, webSocketTask t: URLSessionWebSocketTask,
                    didCloseWith code: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        if t === task { dropped() }
    }

    func urlSession(_ s: URLSession, task t: URLSessionTask, didCompleteWithError e: Error?) {
        if t === task { dropped() }
    }

    func send(_ message: [String: Any]) {
        guard connected, let t = task,
              let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else { return }
        t.send(.string(text)) { [weak self] err in
            if err != nil, let self, t === self.task { self.dropped() }
        }
    }
}
