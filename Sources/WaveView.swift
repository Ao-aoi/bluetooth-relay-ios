import SwiftUI

/// 心電図の波形を描く。縦軸は表示中の最小値〜最大値に合わせる。
struct WaveView: View {
    let samples: [Int]
    let length: Int

    var body: some View {
        Canvas { ctx, size in
            guard samples.count > 1, let lo = samples.min(), let hi = samples.max() else { return }
            let range = Double(max(hi - lo, 1))
            var path = Path()
            for (i, v) in samples.enumerated() {
                let x = size.width * Double(i) / Double(length - 1)
                let y = size.height * (1 - Double(v - lo) / range)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(path, with: .color(.red), lineWidth: 1)
        }
        .frame(height: 160)
        .background(Color(.secondarySystemBackground))
    }
}
