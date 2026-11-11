import SwiftUI

/// 心電図の波形を描き、検出したR波の位置に印を付ける。縦軸は表示中の最小値〜最大値に合わせる。
struct WaveView: View {
    @ObservedObject var store: WaveStore
    let length: Int

    var body: some View {
        Canvas { ctx, size in
            let s = store.wave.samples
            guard s.count > 1, let lo = s.min(), let hi = s.max() else { return }
            let range = max(hi - lo, 1)
            let shift = length - s.count          // 点が少ないうちは右に寄せる
            let top = 8.0
            let h = Double(size.height) - top - 2
            func point(_ i: Int) -> CGPoint {
                CGPoint(x: Double(size.width) * Double(i + shift) / Double(length - 1),
                        y: top + h * (1 - (s[i] - lo) / range))
            }
            var path = Path()
            path.move(to: point(0))
            for i in 1..<s.count { path.addLine(to: point(i)) }
            ctx.stroke(path, with: .color(.red), lineWidth: 1)
            // R波の印(波形の上に▼)
            var marks = Path()
            for p in store.wave.peaks where p < s.count {
                let c = point(p)
                marks.move(to: CGPoint(x: c.x - 4, y: 0))
                marks.addLine(to: CGPoint(x: c.x + 4, y: 0))
                marks.addLine(to: CGPoint(x: c.x, y: 7))
                marks.closeSubpath()
            }
            ctx.fill(marks, with: .color(.blue))
        }
        .frame(height: 160)
        .background(Color(.secondarySystemBackground))
    }
}
