import Foundation
import UIKit

/// グラフに描く1拍ぶんの値。
struct BeatPoint {
    let t: Double                 // 測定開始からの経過秒
    let hr: Double                // 心拍数[bpm]
    let rir: Double?              // RiR(まだ出ていなければ nil)
    let sumrirPerSpan: Double?    // ΣRiR ÷ 積算時間
    let dHR: Double               // 心拍数 − 安静時心拍
}

/// 解析の設定。変えると解析を最初からやり直す。
struct AnalysisSettings: Equatable {
    var hr0 = 60.0          // 安静時心拍[bpm]
    var intSpan = 180.0     // 平均する時間[秒]
    var validSpan = 120.0   // RiRが有効になるまでの時間[秒]
    var sumrirSpan = 120.0  // ΣRiRの積算時間[秒]

    static func load() -> AnalysisSettings {
        let d = UserDefaults.standard
        var s = AnalysisSettings()
        if let v = d.object(forKey: "hr0") as? Double { s.hr0 = v }
        if let v = d.object(forKey: "intSpan") as? Double { s.intSpan = v }
        if let v = d.object(forKey: "validSpan") as? Double { s.validSpan = v }
        if let v = d.object(forKey: "sumrirSpan") as? Double { s.sumrirSpan = v }
        return s
    }

    func save() {
        let d = UserDefaults.standard
        d.set(hr0, forKey: "hr0")
        d.set(intSpan, forKey: "intSpan")
        d.set(validSpan, forKey: "validSpan")
        d.set(sumrirSpan, forKey: "sumrirSpan")
    }
}

/// 接続タブに出す心電図の波形(直近5秒)と、その中のR波の位置。
struct Wave {
    var samples: [Double] = []
    var filtered: [Double] = [] // 前処理後(5点移動平均+5〜25Hz帯域通過)。samples と右端をそろえる
    var peaks: [Int] = []       // samples の中の位置
}

/// 波形は0.2秒ごとに変わるので、1秒ごとに変わる解析結果とは別に持つ。
final class WaveStore: ObservableObject {
    @Published var wave = Wave()
}

/// 解析の本体(EcgSession)を持ち、画面に出す値を1秒に1回まとめて更新する。
final class AnalysisModel: ObservableObject {
    @Published private(set) var points: [BeatPoint] = []
    @Published private(set) var heartRate: Double? = nil
    @Published private(set) var rir: Double? = nil
    @Published private(set) var validSec = 0.0          // RiRが出るまでに溜まった時間[秒]
    @Published private(set) var quality: SignalQuality? = nil
    @Published private(set) var state = ActivityState.unknown
    @Published private(set) var lostPackets = 0
    @Published private(set) var elapsed = 0.0           // 測定開始からの経過秒
    @Published private(set) var settings: AnalysisSettings
    @Published private(set) var loading: Double? = nil  // 記録を読み込み中なら進み具合(0〜1)
    @Published private(set) var resumedNote = ""         // 前の記録の続きから始めたときの説明

    let recorder = Recorder()
    private var pending: [(UInt8, Data)] = []   // 読み込み中に届いたパケット

    let waveStore = WaveStore()
    let mirror = MirrorClient()
    private var mirrored = 0        // PCへ送り終えた拍の数
    private static let mirrorHistory = 3600   // PCにつながったときに送り直す拍の数(最大)
    static let waveLength = 1250    // 250Hz × 5秒

    private var session: EcgSession
    private var copied = 0          // points へ写し終えた拍の数
    private var sincePublish = 0    // 前回の画面更新から受け取った心電パケットの数

    init() {
        let s = AnalysisSettings.load()
        settings = s
        session = AnalysisModel.makeSession(s)
        resumeIfRecent()
        mirror.onOpen = { [weak self] in
            guard let self else { return }
            self.mirrored = max(0, self.points.count - AnalysisModel.mirrorHistory)
            self.sendMirror()
        }
    }

    /// PCの画面に出す名前。設定で付けていなければ、iPhoneの名前。
    static var deviceLabel: String {
        let s = UserDefaults.standard.string(forKey: "deviceLabel") ?? ""
        return s.isEmpty ? UIDevice.current.name : s
    }

    /// 解析結果をPCへ送る。前回送った後に増えた拍だけを付ける。
    /// "from" は beats の先頭が何拍目かを表す。PCはそこから後ろを置き換える。
    private func sendMirror() {
        guard mirror.connected else { return }
        let new = points[min(mirrored, points.count)...]
        let beats: [[Any]] = new.map { [$0.t, $0.hr, $0.rir.map { $0 as Any } ?? NSNull()] }
        mirror.send([
            "name": AnalysisModel.deviceLabel,
            "elapsed": elapsed,
            "hr": heartRate.map { $0 as Any } ?? NSNull(),
            "rir": rir.map { $0 as Any } ?? NSNull(),
            "validSec": validSec,
            "validSpan": settings.validSpan,
            "quality": quality.map { $0.level as Any } ?? NSNull(),
            "state": state.rawValue,
            "from": min(mirrored, points.count),
            "beats": beats,
        ])
        mirrored = points.count
    }

    private static func makeSession(_ s: AnalysisSettings) -> EcgSession {
        EcgSession(ecg: RealtimeECG(hr0: s.hr0, validSpan: s.validSpan, intSpan: s.intSpan, sumrirSpan: s.sumrirSpan))
    }

    /// 心電計から届いたパケット(心電・動き)。記録ファイルに書き、解析に渡す。
    func receive(kind: UInt8, data: Data) {
        if loading != nil { pending.append((kind, data)); return }
        recorder.write(kind: kind, data)
        if kind == 0x01, let p = EcgPacket([UInt8](data)) { onEcg(p) }
        else if kind == 0x02, let p = GyroPacket([UInt8](data)) { onGyro(p) }
    }

    /// 最後の記録が設定の時間(既定5分)以内なら、その記録を流し直して続きから始める。
    private func resumeIfRecent() {
        let minutes = UserDefaults.standard.object(forKey: "resumeMinutes") as? Double ?? 5
        guard minutes > 0, let last = RecordStore.list().first,
              Date().timeIntervalSince(last.modified) <= minutes * 60 else { return }
        let f = DateFormatter(); f.dateFormat = "H:mm"
        load(last.url, note: "\(f.string(from: last.start)) からの記録の続き")
    }

    /// 記録ファイルを流し直して解析を作り直し、そのファイルに続けて記録する。
    private func load(_ url: URL, note: String) {
        guard let data = try? Data(contentsOf: url) else { return }
        loading = 0
        let s = AnalysisModel.makeSession(settings)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            Recording.replay([UInt8](data), into: s) { p in
                DispatchQueue.main.async { if self?.loading != nil { self?.loading = p } }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.session = s
                self.copied = 0
                self.points = []
                self.recorder.resume(url)
                self.loading = nil
                self.resumedNote = note
                self.publish()
                let p = self.pending
                self.pending = []
                for (k, d) in p { self.receive(kind: k, data: d) }
            }
        }
    }

    private func onEcg(_ pkt: EcgPacket) {
        session.onPacket(pkt)
        let e = session.ecg
        let a = e.adc.suffix(AnalysisModel.waveLength)
        let first = e.n - a.count       // a の先頭の通し番号
        waveStore.wave = Wave(samples: Array(a), filtered: Array(e.f.suffix(a.count)), peaks: e.kept.suffix(40).map { $0 - first }.filter { $0 >= 0 })
        sincePublish += 1
        if sincePublish >= 5 { publish() }      // 心電パケットは0.2秒ごとなので、5個で1秒
    }

    private func onGyro(_ pkt: GyroPacket) {
        session.onGyro(pkt)
    }

    private func publish() {
        sincePublish = 0
        let e = session.ecg
        let beats = e.beats
        if beats.count > copied {
            points.append(contentsOf: beats[copied...].map {
                BeatPoint(t: $0.timeS, hr: $0.hrBpm, rir: $0.rir, sumrirPerSpan: $0.sumrirPerSpan, dHR: $0.dHR)
            })
            copied = beats.count
        }
        heartRate = beats.last?.hrBpm
        rir = beats.last?.rir
        validSec = e.rir.validSec()
        quality = e.quality()
        state = session.activity.state
        lostPackets = session.lost
        elapsed = Double(e.n) / Double(e.fs)
        sendMirror()
    }

    /// 設定を変えて、今の記録を最初から解析し直す(記録は消さない)。
    func reanalyze(with new: AnalysisSettings) {
        settings = new
        new.save()
        guard loading == nil else { return }
        if let u = recorder.url {
            recorder.close()
            load(u, note: resumedNote)
        } else {
            restart()
        }
    }

    /// 解析を最初からやり直す。次に届いたパケットからは新しい記録ファイルに書く(前の記録は履歴に残る)。
    func restart() {
        guard loading == nil else { return }
        recorder.close()
        resumedNote = ""
        session = AnalysisModel.makeSession(settings)
        copied = 0
        sincePublish = 0
        points = []
        waveStore.wave = Wave()
        heartRate = nil; rir = nil; validSec = 0; quality = nil
        state = .unknown; lostPackets = 0; elapsed = 0
        mirrored = 0
        sendMirror()
    }
}
