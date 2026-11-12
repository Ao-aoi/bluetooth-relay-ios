import SwiftUI

/// 設定タブ: グラフの時間範囲と、解析の設定。
struct SettingsTab: View {
    @ObservedObject var model: AnalysisModel
    @AppStorage("rangeMinutes") private var rangeMinutes = 10.0
    @AppStorage("rangeAll") private var rangeAll = false
    @AppStorage("useSwiftCharts") private var useSwiftCharts = false
    @AppStorage("autoScanDevice") private var autoScanDevice = false
    @AppStorage("autoFindPC") private var autoFindPC = false
    @AppStorage("deviceLabel") private var deviceLabel = ""
    @State private var rangeText = ""
    @AppStorage("resumeMinutes") private var resumeMinutes = 5.0
    @State private var resumeText = ""
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
            Section("PCの画面に出す名前") {
                TextField(UIDevice.current.name, text: $deviceLabel)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
            }
            Section("記録") {
                field("続きとして扱う間隔 [分]", $resumeText)
                    .onChange(of: resumeText) { t in
                        if let v = Double(t), v >= 0, v <= 1440 { resumeMinutes = v }
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
                Button("この値で今の記録を解析し直す") { askApply = true }
                    .disabled(draft == nil || draft == model.settings)
                Button("既定値に戻す") { fill(AnalysisSettings()) }
            }
            Section {
                Button("新しい記録を始める", role: .destructive) { askRestart = true }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onReceive(model.$settings) { fill($0) }
        .onAppear {
            rangeText = String(format: "%g", rangeMinutes)
            resumeText = String(format: "%g", resumeMinutes)
        }
        .alert("今の記録を、新しい設定で最初から解析し直します", isPresented: $askApply) {
            Button("やり直す") { if let d = draft { model.reanalyze(with: d) } }
            Button("やめる", role: .cancel) {}
        }
        .alert("今の記録を終えて、新しい記録を始めます。今の記録は履歴タブに残ります", isPresented: $askRestart) {
            Button("新しい記録を始める", role: .destructive) { model.restart() }
            Button("やめる", role: .cancel) {}
        }
    }
}
