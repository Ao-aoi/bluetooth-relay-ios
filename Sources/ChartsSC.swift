import SwiftUI
import Charts

/// Swift Charts で描く版(設定の「描き方」で切り替える)。Canvas版と同じデータを同じ範囲で描く。
struct ChartSample: Identifiable {
    let id: Int
    let x: Double
    let y: Double
    let group: Int      // 折れ線: 線を切る単位。散布図: 1 が最新の拍
}

struct LineChartSC: View {
    let points: [BeatPoint]
    let value: (BeatPoint) -> Double?
    let xRange: ClosedRange<Double>     // 経過秒
    let yRange: ClosedRange<Double>
    let color: Color

    /// 表示範囲の拍を最大約600点に間引く。値が nil の拍で group を変えて線を切る。
    private var samples: [ChartSample] {
        let visible = points.filter { $0.t >= xRange.lowerBound && $0.t <= xRange.upperBound }
        let step = max(1, visible.count / 600)
        var out = [ChartSample]()
        var group = 0
        var i = 0
        while i < visible.count {
            if let v = value(visible[i]) {
                let y = min(max(v, yRange.lowerBound), yRange.upperBound)
                out.append(ChartSample(id: i, x: visible[i].t / 60, y: y, group: group))
            } else {
                group += 1
            }
            i += step
        }
        return out
    }

    var body: some View {
        Chart(samples) { s in
            LineMark(x: .value("時間", s.x), y: .value("値", s.y), series: .value("区間", s.group))
                .foregroundStyle(color)
        }
        .chartXScale(domain: (xRange.lowerBound / 60)...(xRange.upperBound / 60))
        .chartYScale(domain: yRange)
        .chartLegend(.hidden)
    }
}

struct ScatterChartSC: View {
    let points: [BeatPoint]
    let xMax: Double

    private var samples: [ChartSample] {
        let step = max(1, points.count / 1500)
        var out = [ChartSample]()
        var i = 0
        while i < points.count {
            if let v = points[i].sumrirPerSpan {
                out.append(ChartSample(id: i, x: min(max(points[i].dHR, 0), xMax), y: min(max(v, 0), 1), group: 0))
            }
            i += step
        }
        if let last = points.last, let v = last.sumrirPerSpan {
            out.append(ChartSample(id: points.count, x: min(max(last.dHR, 0), xMax), y: min(max(v, 0), 1), group: 1))
        }
        return out
    }

    var body: some View {
        Chart(samples) { s in
            PointMark(x: .value("ΔHR", s.x), y: .value("ΣRiR", s.y))
                .symbolSize(s.group == 1 ? 60 : 10)
                .foregroundStyle(s.group == 1 ? Color.red : Color.blue.opacity(0.45))
        }
        .chartXScale(domain: 0...xMax)
        .chartYScale(domain: 0...1)
        .chartLegend(.hidden)
    }
}
