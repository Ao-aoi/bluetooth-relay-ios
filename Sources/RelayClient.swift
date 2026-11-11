import Foundation

/// PCへ WebSocket(ws://<PC>:9750)でBLEパケットをそのまま送る。
/// 形式: 1バイトの種類(0x01=心電, 0x02=動き, 0x03=5秒ごと) + BLEパケット。
/// PCにつながっていない間はためておき、PCが文字メッセージ "pull" を送ってきたら全部送る。
final class RelayClient: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    @Published var running = false
    @Published var connected = false
    @Published var bufferedCount = 0
    @Published var sentCount = 0

    static let port = 9750
    private let maxBuffer = 400_000          // 約1時間以上ぶん
    private var buffer: [Data] = []
    private var flushing = false
    private var host = ""
    private var task: URLSessionWebSocketTask?
    private var session: URLSession!
    private var retry: Timer?

    override init() {
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    }

    func start(host: String) {
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
        task = session.webSocketTask(with: url)
        task?.resume()
        listen(task)
    }

    private func listen(_ t: URLSessionWebSocketTask?) {
        t?.receive { [weak self] result in
            guard let self, t === self.task else { return }
            switch result {
            case .success(let msg):
                if case .string(let s) = msg, s.hasPrefix("pull") { self.flush() }
                self.listen(t)
            case .failure:
                self.dropped()
            }
        }
    }

    private func dropped() {
        task = nil
        connected = false
        flushing = false
    }

    func urlSession(_ s: URLSession, webSocketTask t: URLSessionWebSocketTask, didOpenWithProtocol p: String?) {
        connected = true
        t.send(.string("hello buffered=\(buffer.count)")) { _ in }
    }

    func urlSession(_ s: URLSession, webSocketTask t: URLSessionWebSocketTask,
                    didCloseWith code: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        if t === task { dropped() }
    }

    func urlSession(_ s: URLSession, task t: URLSessionTask, didCompleteWithError e: Error?) {
        if t === task { dropped() }
    }

    func send(kind: UInt8, packet: Data) {
        var m = Data([kind]); m.append(packet)
        if connected, !flushing, let t = task {
            t.send(.data(m)) { [weak self] err in
                guard let self else { return }
                if err == nil { self.sentCount += 1 } else { self.keep(m); self.dropped() }
            }
        } else {
            keep(m)
        }
    }

    private func keep(_ m: Data) {
        buffer.append(m)
        if buffer.count > maxBuffer { buffer.removeFirst(buffer.count - maxBuffer) }
        bufferedCount = buffer.count
    }

    /// ためた分を古い順に全部送る。その間に来た新しいパケットは後ろに並べて順序を保つ。
    private func flush() {
        guard !flushing, connected, let t = task else { return }
        flushing = true
        func next() {
            guard connected, t === task, !buffer.isEmpty else {
                flushing = false; bufferedCount = buffer.count; return
            }
            let m = buffer.removeFirst()
            bufferedCount = buffer.count
            t.send(.data(m)) { [weak self] err in
                guard let self else { return }
                if err == nil { self.sentCount += 1; next() }
                else { self.buffer.insert(m, at: 0); self.bufferedCount = self.buffer.count; self.dropped() }
            }
        }
        next()
    }
}
