import SwiftUI

/// グラフの外枠と目盛りの余白。
private let marginLeft = 34.0, marginRight = 8.0, marginTop = 6.0, marginBottom = 16.0

private func label(_ s: String) -> Text {
    Text(s).font(.system(size: 10)).foregroundColor(.secondary)
}

/// 横軸が経過時間の折れ線グラフ。値が nil の拍では線を切る。
struct LineChart: View {
    let points: [BeatPoint]
    let value: (BeatPoint) -> Double?
    let xRange: ClosedRange<Double>     // 経過秒
    let yRange: ClosedRange<Double>
    let yStep: Double
    let color: Color

    /// 横軸の目盛りの間隔[秒]。目盛りが6本以下になるものを選ぶ。
    private var xStep: Double {
        let span = xRange.upperBound - xRange.lowerBound
        for m in [1.0, 2, 5, 10, 30, 60] where span / (m * 60) <= 6 { return m * 60 }
        return 120 * 60
    }

    /// xRange の左端以降で最初の拍の位置(二分探索)。
    private var firstIndex: Int {
        var lo = 0, hi = points.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if points[mid].t < xRange.lowerBound { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    var body: some View {
        Canvas { ctx, size in
            let w = Double(size.width) - marginLeft - marginRight
            let h = Double(size.height) - marginTop - marginBottom
            guard w > 10, h > 10 else { return }
            let xSpan = xRange.upperBound - xRange.lowerBound
            let ySpan = yRange.upperBound - yRange.lowerBound
            func px(_ t: Double) -> Double { marginLeft + w * (t - xRange.lowerBound) / xSpan }
            func py(_ v: Double) -> Double { marginTop + h * (1 - (v - yRange.lowerBound) / ySpan) }

            // 目盛りの線と数字
            var grid = Path()
            var y = yRange.lowerBound
            while y <= yRange.upperBound + 1e-9 {
                grid.move(to: CGPoint(x: marginLeft, y: py(y)))
                grid.addLine(to: CGPoint(x: marginLeft + w, y: py(y)))
                let s = yStep < 1 ? String(format: "%.1f", y) : String(format: "%.0f", y)
                ctx.draw(label(s), at: CGPoint(x: marginLeft - 4, y: py(y)), anchor: .trailing)
                y += yStep
            }
            var x = (xRange.lowerBound / xStep).rounded(.up) * xStep
            while x <= xRange.upperBound + 1e-9 {
                grid.move(to: CGPoint(x: px(x), y: marginTop))
                grid.addLine(to: CGPoint(x: px(x), y: marginTop + h))
                ctx.draw(label(String(format: "%.0f", x / 60)), at: CGPoint(x: px(x), y: marginTop + h + 2), anchor: .top)
                x += xStep
            }
            ctx.stroke(grid, with: .color(.secondary.opacity(0.25)), lineWidth: 0.5)

            // 折れ線。点が横幅より多いときは間引く
            let start = firstIndex
            let n = points.count - start
            guard n > 0 else { return }
            let step = max(1, n / Int(w * 2))
            var path = Path()
            var penDown = false
            var i = start
            while i < points.count {
                let p = points[i]
                if p.t > xRange.upperBound { break }
                if let v = value(p) {
                    let pt = CGPoint(x: px(p.t), y: py(min(max(v, yRange.lowerBound), yRange.upperBound)))
                    if penDown { path.addLine(to: pt) } else { path.move(to: pt); penDown = true }
                } else {
                    penDown = false
                }
                i += step
            }
            ctx.stroke(path, with: .color(color), lineWidth: 1.2)
        }
        .background(Color(.secondarySystemBackground))
    }
}

/// 散布図。横軸 ΔHR、縦軸 ΣRiR ÷ 積算時間。最新の拍を赤で描く。
struct ScatterChart: View {
    let points: [BeatPoint]
    let xMax: Double
    let yLabel: String

    var body: some View {
        Canvas { ctx, size in
            let w = Double(size.width) - marginLeft - marginRight
            let h = Double(size.height) - marginTop - marginBottom
            guard w > 10, h > 10 else { return }
            func px(_ v: Double) -> Double { marginLeft + w * min(max(v, 0), xMax) / xMax }
            func py(_ v: Double) -> Double { marginTop + h * (1 - min(max(v, 0), 1)) }

            var grid = Path()
            for k in 0...5 {
                let y = Double(k) * 0.2
                grid.move(to: CGPoint(x: marginLeft, y: py(y)))
                grid.addLine(to: CGPoint(x: marginLeft + w, y: py(y)))
                ctx.draw(label(String(format: "%.1f", y)), at: CGPoint(x: marginLeft - 4, y: py(y)), anchor: .trailing)
            }
            var x = 0.0
            while x <= xMax + 1e-9 {
                grid.move(to: CGPoint(x: px(x), y: marginTop))
                grid.addLine(to: CGPoint(x: px(x), y: marginTop + h))
                ctx.draw(label(String(format: "%.0f", x)), at: CGPoint(x: px(x), y: marginTop + h + 2), anchor: .top)
                x += 20
            }
            ctx.stroke(grid, with: .color(.secondary.opacity(0.25)), lineWidth: 0.5)
            ctx.draw(label(yLabel), at: CGPoint(x: marginLeft + 4, y: marginTop + 2), anchor: .topLeading)
            ctx.draw(label("ΔHR"), at: CGPoint(x: marginLeft + w - 2, y: marginTop + h - 2), anchor: .bottomTrailing)

            // 点が多いときは間引く(最大約1500点)
            let step = max(1, points.count / 1500)
            var dots = Path()
            var i = 0
            while i < points.count {
                if let v = points[i].sumrirPerSpan {
                    dots.addEllipse(in: CGRect(x: px(points[i].dHR) - 1.5, y: py(v) - 1.5, width: 3, height: 3))
                }
                i += step
            }
            ctx.fill(dots, with: .color(.blue.opacity(0.45)))
            if let last = points.last, let v = last.sumrirPerSpan {
                let r = CGRect(x: px(last.dHR) - 4, y: py(v) - 4, width: 8, height: 8)
                ctx.fill(Path(ellipseIn: r), with: .color(.red))
            }
        }
        .background(Color(.secondarySystemBackground))
    }
}
