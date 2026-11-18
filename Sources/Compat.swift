import SwiftUI
import UIKit

// iOS 15 でも動かすための部品。iOS 16 以降で使える部品は #available で切り替える。

/// 「名前 …… 値」の1行。iOS 16 の LabeledContent と同じ見た目。
struct Row<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        if #available(iOS 16, *) {
            LabeledContent(title) { content }
        } else {
            HStack {
                Text(title)
                Spacer()
                content.foregroundColor(.secondary)
            }
        }
    }
}

extension Row where Content == Text {
    init(_ title: String, value: String) {
        self.init(title) { Text(value) }
    }
}

/// 画面の切り替え(履歴の一覧 → 詳細)。iOS 16 以降は NavigationStack、iOS 15 は NavigationView。
struct NavigationContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(iOS 16, *) {
            NavigationStack { content() }
        } else {
            NavigationView { content() }.navigationViewStyle(.stack)
        }
    }
}

/// ファイルを他のアプリへ送るボタン。iOS 16 以降は ShareLink、iOS 15 は共有シートを開く。
struct ShareFileButton: View {
    let url: URL
    let title: String
    @State private var showSheet = false

    var body: some View {
        if #available(iOS 16, *) {
            ShareLink(item: url) { Label(title, systemImage: "square.and.arrow.up") }
        } else {
            Button { showSheet = true } label: { Label(title, systemImage: "square.and.arrow.up") }
                .sheet(isPresented: $showSheet) { ActivitySheet(items: [url]) }
        }
    }
}

/// iOS 15 用の共有シート(UIKit の UIActivityViewController)。
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

extension View {
    /// スクロールでキーボードを閉じる。iOS 15 では何もしない(キーボードの「完了」で閉じる)。
    @ViewBuilder
    func dismissKeyboardOnScroll() -> some View {
        if #available(iOS 16, *) {
            self.scrollDismissesKeyboard(.interactively)
        } else {
            self
        }
    }
}

/// Swift Charts は iOS 16 以降だけ。iOS 15 では設定に関係なく Canvas で描く。
var swiftChartsAvailable: Bool {
    if #available(iOS 16, *) { return true }
    return false
}
