import SwiftUI

/// 心電図の波形を1本描き、検出したR波の位置に▼を付ける。縦軸は表示中の最小値〜最大値に合わせる。
struct WaveCanvas: View {
    let s: [Double]
    let peaks: [Int]       // 右端からの位置を合わせるため、s の末尾が最新
    let offset: Int        // peaks の位置から s の位置へのずれ
    let length: Int
    let color: Color

    var body: some View {
        Canvas { ctx, size in
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
            ctx.stroke(path, with: .color(color), lineWidth: 1)
            var marks = Path()
            for p0 in peaks {
                let p = p0 - offset
                guard p >= 0, p < s.count else { continue }
                let c = point(p)
                marks.move(to: CGPoint(x: c.x - 4, y: 0))
                marks.addLine(to: CGPoint(x: c.x + 4, y: 0))
                marks.addLine(to: CGPoint(x: c.x, y: 7))
                marks.closeSubpath()
            }
            ctx.fill(marks, with: .color(.blue))
        }
        .background(Color(.secondarySystemBackground))
    }
}

/// 生波形と、その下に前処理後の波形を並べる。
struct WaveView: View {
    @ObservedObject var store: WaveStore
    let length: Int

    var body: some View {
        let w = store.wave
        VStack(alignment: .leading, spacing: 4) {
            Text("生波形").font(.caption).foregroundColor(.secondary)
            WaveCanvas(s: w.samples, peaks: w.peaks, offset: 0, length: length, color: .red)
                .frame(height: 120)
            Text("前処理後").font(.caption).foregroundColor(.secondary)
            WaveCanvas(s: w.filtered, peaks: w.peaks, offset: w.samples.count - w.filtered.count,
                       length: length, color: .primary)
                .frame(height: 120)
        }
    }
}
