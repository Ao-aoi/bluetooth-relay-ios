import SwiftUI

/// 設定タブ: グラフの時間範囲と、解析の設定。
struct SettingsTab: View {
    @ObservedObject var model: AnalysisModel
    @AppStorage("rangeMinutes") private var rangeMinutes = 10.0
    @AppStorage("rangeAll") private var rangeAll = false
    @AppStorage("useSwiftCharts") private var useSwiftCharts = false
    @AppStorage("autoScanDevice") private var autoScanDevice = false
    @AppStorage("autoFindPC") private var autoFindPC = false
    @State private var rangeText = ""
    @State private var hr0 = ""
    @State private var intSpan = ""
    @State private var validSpan = ""
    @State private var sumrirSpan = ""
    @State private var askApply = false
    @State private var askRestart = false

    /// 入力欄の値。数値でない、または範囲の外なら nil。
    private var draft: AnalysisSettings? {
        guard let a = Double(hr0), let b = Double(intSpan), let c = Double(validSpan), let d = Double(sumrirSpan),
              a >= 30, a <= 120, b >= 30, b <= 600, c >= 10, c <= b, d >= 30, d <= 600 else { return nil }
        return AnalysisSettings(hr0: a, intSpan: b, validSpan: c, sumrirSpan: d)
    }

    private func fill(_ s: AnalysisSettings) {
        hr0 = String(format: "%.0f", s.hr0)
        intSpan = String(format: "%.0f", s.intSpan)
        validSpan = String(format: "%.0f", s.validSpan)
        sumrirSpan = String(format: "%.0f", s.sumrirSpan)
    }

    private func field(_ title: String, _ text: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField("", text: text)
                .keyboardType(.numbersAndPunctuation)
                .submitLabel(.done)
                .multilineTextAlignment(.trailing)
        }
    }

    var body: some View {
        Form {
            Section("グラフ") {
                field("表示する時間 [分]", $rangeText)
                    .disabled(rangeAll)
                    .onChange(of: rangeText) { t in
                        if let v = Double(t), v >= 0.5, v <= 1440 { rangeMinutes = v }
                    }
                Toggle("測定の全体を表示", isOn: $rangeAll)
                Picker("描き方", selection: $useSwiftCharts) {
                    Text("Canvas").tag(false)
                    Text("Swift Charts").tag(true)
                }
            }
            Section("起動時") {
                Toggle("心電計を探す", isOn: $autoScanDevice)
                Toggle("PCを探す", isOn: $autoFindPC)
            }
            Section("解析") {
                field("安静時心拍 [bpm]", $hr0)
                field("平均する時間 [秒]", $intSpan)
                field("有効になるまでの時間 [秒]", $validSpan)
                field("ΣRiRの積算時間 [秒]", $sumrirSpan)
                Button("この値で解析をやり直す") { askApply = true }
                    .disabled(draft == nil || draft == model.settings)
                Button("既定値に戻す") { fill(AnalysisSettings()) }
            }
            Section {
                Button("解析をやり直す", role: .destructive) { askRestart = true }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onReceive(model.$settings) { fill($0) }
        .onAppear { rangeText = String(format: "%g", rangeMinutes) }
        .alert("解析を最初からやり直します", isPresented: $askApply) {
            Button("やり直す") { if let d = draft { model.restart(with: d) } }
            Button("やめる", role: .cancel) {}
        }
        .alert("解析の途中経過とグラフを消します", isPresented: $askRestart) {
            Button("消してやり直す", role: .destructive) { model.restart() }
            Button("やめる", role: .cancel) {}
        }
    }
}
