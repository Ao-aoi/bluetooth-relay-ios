import SwiftUI

/// 履歴タブ: 過去の記録の一覧。選ぶと、その記録を解析し直してグラフを出す。
struct HistoryTab: View {
    @ObservedObject var model: AnalysisModel
    @State private var files: [RecordFile] = []
    @State private var deleting: RecordFile? = nil

    static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日(E) H:mm"
        return f
    }()

    private func reload() { files = RecordStore.list() }

    var body: some View {
        NavigationStack {
            List {
                if files.isEmpty { Text("記録はまだありません").foregroundColor(.secondary) }
                ForEach(files) { f in
                    NavigationLink(value: f) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(HistoryTab.dateFormat.string(from: f.start))
                            HStack {
                                Text(String(format: "約%.0f分", f.approxSeconds / 60))
                                if f.url == model.recorder.url { Text("記録中").foregroundColor(.red) }
                            }
                            .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .swipeActions {
                        if f.url != model.recorder.url {
                            Button("削除", role: .destructive) { deleting = f }
                        }
                    }
                }
            }
            .navigationTitle("履歴")
            .navigationDestination(for: RecordFile.self) { f in
                HistoryDetail(file: f, settings: model.settings)
            }
            .refreshable { reload() }
            .onAppear { reload() }
            .alert("この記録を削除します", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("削除", role: .destructive) {
                    if let f = deleting { try? FileManager.default.removeItem(at: f.url) }
                    deleting = nil
                    reload()
                }
                Button("やめる", role: .cancel) { deleting = nil }
            }
        }
    }
}

/// 1つの記録の解析結果。今の設定(安静時心拍など)で解析し直して表示する。
struct HistoryDetail: View {
    let file: RecordFile
    let settings: AnalysisSettings
    @AppStorage("useSwiftCharts") private var useSwiftCharts = false
    @State private var points: [BeatPoint] = []
    @State private var progress: Double? = 0
    @State private var lost = 0

    private var duration: Double { max(points.last?.t ?? 60, 60) }

    private var summary: [(String, String)] {
        let hrs = points.map { $0.hr }
        let rirs = points.compactMap { $0.rir }
        func f(_ v: Double?, _ fmt: String) -> String { v.map { String(format: fmt, $0) } ?? "--" }
        return [
            ("記録時間", String(format: "%.1f 分", duration / 60)),
            ("拍の数", "\(points.count)"),
            ("心拍数 平均", f(hrs.isEmpty ? nil : hrs.reduce(0, +) / Double(hrs.count), "%.0f bpm")),
            ("心拍数 最大", f(hrs.max(), "%.0f bpm")),
            ("RiR 最大", f(rirs.max(), "%.3f")),
            ("届かなかったパケット", "\(lost)"),
        ]
    }

    @ViewBuilder
    private func line(_ value: @escaping (BeatPoint) -> Double?, _ y: ClosedRange<Double>, _ step: Double, _ c: Color) -> some View {
        if useSwiftCharts {
            LineChartSC(points: points, value: value, xRange: 0...duration, yRange: y, color: c)
        } else {
            LineChart(points: points, value: value, xRange: 0...duration, yRange: y, yStep: step, color: c)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let p = progress {
                    ProgressView("解析中", value: p)
                } else {
                    Text("心拍数").font(.subheadline)
                    line({ $0.hr }, 40...200, 20, .red).frame(height: 160)
                    Text("RiR").font(.subheadline)
                    line({ $0.rir }, 0...1, 0.2, .blue).frame(height: 160)
                    Text("時間 [分]").font(.caption2).foregroundColor(.secondary)
                    Group {
                        if useSwiftCharts {
                            ScatterChartSC(points: points, xMax: 140)
                        } else {
                            ScatterChart(points: points, xMax: 140, yLabel: String(format: "ΣRiR/%.0f", settings.sumrirSpan))
                        }
                    }
                    .frame(height: 220)
                    ForEach(summary, id: \.0) { k, v in
                        HStack { Text(k); Spacer(); Text(v).monospacedDigit() }.font(.subheadline)
                    }
                    ShareLink(item: file.url) { Label("記録ファイルを送る", systemImage: "square.and.arrow.up") }
                        .padding(.top, 6)
                }
            }
            .padding()
        }
        .navigationTitle(HistoryTab.dateFormat.string(from: file.start))
        .navigationBarTitleDisplayMode(.inline)
        .task { await analyze() }
    }

    private func analyze() async {
        guard let data = try? Data(contentsOf: file.url) else { progress = nil; return }
        let s = settings
        let session = EcgSession(ecg: RealtimeECG(hr0: s.hr0, validSpan: s.validSpan, intSpan: s.intSpan, sumrirSpan: s.sumrirSpan))
        await Task.detached(priority: .userInitiated) {
            Recording.replay([UInt8](data), into: session) { p in
                Task { @MainActor in if progress != nil { progress = p } }
            }
        }.value
        points = session.ecg.beats.map {
            BeatPoint(t: $0.timeS, hr: $0.hrBpm, rir: $0.rir, sumrirPerSpan: $0.sumrirPerSpan, dHR: $0.dHR)
        }
        lost = session.lost
        progress = nil
    }
}
