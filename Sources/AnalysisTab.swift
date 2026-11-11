import SwiftUI

/// 解析タブ: 心拍数とRiRのグラフ、散布図、信号品質と状態。
struct AnalysisTab: View {
    @ObservedObject var model: AnalysisModel
    @AppStorage("rangeMinutes") private var rangeMinutes = 10.0   // グラフの時間範囲[分]
    @AppStorage("rangeAll") private var rangeAll = false          // 測定の全体を表示する
    @AppStorage("useSwiftCharts") private var useSwiftCharts = false
    @State private var hr0Text = ""
    @State private var askRestart = false

    /// グラフの横軸の範囲[秒]。
    private var xRange: ClosedRange<Double> {
        if rangeAll { return 0...max(model.elapsed, 60) }
        let span = max(rangeMinutes, 0.5) * 60
        let lo = max(0, model.elapsed - span)
        return lo...(lo + span)
    }

    /// 心拍数グラフの縦軸。表示中の拍に合わせて10bpm単位で広げる。
    private var hrRange: ClosedRange<Double> {
        let r = xRange
        var lo = 50.0, hi = 120.0
        for p in model.points.reversed() {
            if p.t < r.lowerBound { break }
            lo = min(lo, (p.hr / 10).rounded(.down) * 10)
            hi = max(hi, (p.hr / 10).rounded(.up) * 10)
        }
        return max(lo, 30)...min(hi, 230)
    }

    private var hrText: String {
        model.heartRate.map { String(format: "%.0f bpm", $0) } ?? "--"
    }

    private var rirText: String {
        if let r = model.rir { return String(format: "%.3f", r) }
        if model.heartRate == nil { return "--" }
        let span = model.settings.validSpan
        return String(format: "準備中(%.0f / %.0f 秒)", min(model.validSec, span), span)
    }

    private var qualityLabel: (String, Color) {
        guard let q = model.quality else { return ("--", .secondary) }
        return [("良好", Color.green), ("注意", Color.orange), ("不良", Color.red)][q.level]
    }

    private var stateColor: Color {
        switch model.state {
        case .rest: return .green
        case .light: return .orange
        case .exercise: return .red
        case .unknown: return .secondary
        }
    }

    private func header(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline.monospacedDigit())
        }
    }

    /// 折れ線グラフ。設定に応じて Canvas 版か Swift Charts 版で描く。
    @ViewBuilder
    private func line(_ value: @escaping (BeatPoint) -> Double?, _ yRange: ClosedRange<Double>,
                      _ yStep: Double, _ color: Color) -> some View {
        if useSwiftCharts {
            LineChartSC(points: model.points, value: value, xRange: xRange, yRange: yRange, color: color)
                .frame(maxHeight: .infinity)
        } else {
            LineChart(points: model.points, value: value, xRange: xRange, yRange: yRange, yStep: yStep, color: color)
                .frame(maxHeight: .infinity)
        }
    }

    private func submitHr0() {
        guard let v = Double(hr0Text), v >= 30, v <= 120 else {
            hr0Text = String(format: "%.0f", model.settings.hr0)
            return
        }
        if v != model.settings.hr0 { askRestart = true }
    }

    var body: some View {
        VStack(spacing: 6) {
            header("心拍数", hrText)
            line({ $0.hr }, hrRange, 20, .red)
            header("RiR", rirText)
            line({ $0.rir }, 0...1, 0.2, .blue)
            Text("時間 [分]").font(.caption2).foregroundColor(.secondary)
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if useSwiftCharts {
                        ScatterChartSC(points: model.points, xMax: 140)
                    } else {
                        ScatterChart(points: model.points, xMax: 140,
                                     yLabel: String(format: "ΣRiR/%.0f", model.settings.sumrirSpan))
                    }
                }
                .frame(width: 190, height: 170)
                VStack(alignment: .leading, spacing: 6) {
                    Text("安静時心拍").font(.caption)
                    TextField("60", text: $hr0Text)
                        .keyboardType(.numbersAndPunctuation)
                        .submitLabel(.done)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { submitHr0() }
                    Text("ΔHR").font(.caption)
                    Text(model.points.last.map { String(format: "%.0f", $0.dHR) } ?? "--")
                        .font(.body.monospacedDigit())
                    Text(String(format: "ΣRiR/%.0f", model.settings.sumrirSpan)).font(.caption)
                    Text(model.points.last?.sumrirPerSpan.map { String(format: "%.3f", $0) } ?? "--")
                        .font(.body.monospacedDigit())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Text("信号品質: ") + Text(qualityLabel.0).foregroundColor(qualityLabel.1).bold()
                Spacer()
                Divider().frame(height: 18)
                Spacer()
                Text(model.state.rawValue).foregroundColor(stateColor).bold()
            }
            .font(.subheadline)
            .padding(.bottom, 6)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .ignoresSafeArea(.keyboard)
        .onReceive(model.$settings) { hr0Text = String(format: "%.0f", $0.hr0) }
        .alert("安静時心拍を変えると、解析を最初からやり直します", isPresented: $askRestart) {
            Button("変更する") {
                var s = model.settings
                s.hr0 = Double(hr0Text) ?? s.hr0
                model.restart(with: s)
            }
            Button("やめる", role: .cancel) { hr0Text = String(format: "%.0f", model.settings.hr0) }
        }
    }
}
