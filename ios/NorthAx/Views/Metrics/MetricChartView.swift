import SwiftUI

// Line graph for a single metric series. Hand-rolled with SwiftUI `Path` to
// match the project's existing chart style (see WorkoutEffortGraphView). Shows
// the min/max value on the Y axis and the first/last date on the X axis. In
// `interactive` mode, dragging scrubs a marker that reads off the value + date
// at any point — used by the metric detail modal.
struct MetricChartView: View {
    let values: [Double]
    let dates: [Date]
    let color: Color
    /// Formats a value for the axis labels and the scrub callout (e.g. "58 ms").
    let format: (Double) -> String
    var interactive: Bool = false

    @State private var selectedIndex: Int?

    private let yAxisWidth: CGFloat = 40
    private let vPad: CGFloat = 10   // keep the line off the top/bottom edges

    private var minVal: Double { values.min() ?? 0 }
    private var maxVal: Double { values.max() ?? 1 }
    private var range: Double { Swift.max(maxVal - minVal, 0.0001) }
    private var avgVal: Double { values.reduce(0, +) / Double(values.count) }

    var body: some View {
        if values.count < 2 {
            Text("Not enough history yet")
                .font(.footnote)
                .foregroundStyle(.axTertiary)
                .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            VStack(spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    yAxisLabels
                    chartArea
                }
                xAxisLabels
            }
        }
    }

    // MARK: - Axes

    private var yAxisLabels: some View {
        VStack(alignment: .trailing) {
            Text(format(maxVal))
            Spacer()
            Text(format(minVal))
        }
        .font(.axMono(9))
        .foregroundStyle(.axTertiary)
        .frame(width: yAxisWidth, alignment: .trailing)
        .padding(.vertical, vPad - 4)
    }

    private var xAxisLabels: some View {
        HStack {
            Color.clear.frame(width: yAxisWidth)
            Text(Self.dayLabel.string(from: dates.first ?? Date()).uppercased())
            Spacer()
            Text(Self.dayLabel.string(from: dates.last ?? Date()).uppercased())
        }
        .font(.axMono(9))
        .tracking(0.6)
        .foregroundStyle(.axTertiary)
    }

    // MARK: - Plot

    private var chartArea: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack(alignment: .topLeading) {
                // Fill under the line
                Path { p in
                    p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                    pts.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: pts.last!.x, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.22), color.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    )
                )

                // Series average as a dashed line (same style as ActivityStreamChart).
                let yAvg = vPad + (1 - (avgVal - minVal) / range) * (geo.size.height - vPad * 2)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: yAvg))
                    p.addLine(to: CGPoint(x: geo.size.width, y: yAvg))
                }
                .stroke(color.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                Text("AVG \(format(avgVal))")
                    .font(.axMono(8, .semibold))
                    .foregroundStyle(color.opacity(0.8))
                    .position(x: geo.size.width - 34, y: yAvg < 14 ? yAvg + 9 : yAvg - 7)

                // Line
                Path { p in
                    p.move(to: pts[0])
                    pts.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                if let i = selectedIndex, pts.indices.contains(i) {
                    // Scrub indicator: vertical line + marker dot + value/date callout
                    Rectangle()
                        .fill(color.opacity(0.35))
                        .frame(width: 1, height: geo.size.height)
                        .position(x: pts[i].x, y: geo.size.height / 2)
                    Circle().fill(.white).frame(width: 10, height: 10)
                        .overlay(Circle().stroke(color, lineWidth: 3))
                        .position(pts[i])
                    callout(text: format(values[i]),
                            sub: Self.calloutDate.string(from: dates[i]),
                            x: pts[i].x, width: geo.size.width)
                } else {
                    // Resting dot on the latest reading
                    Circle().fill(color).frame(width: 7, height: 7)
                        .shadow(color: color.opacity(0.5), radius: 6)
                        .position(pts.last!)
                }
            }
            .contentShape(Rectangle())
            .gesture(interactive ? dragGesture(width: geo.size.width) : nil)
        }
        .frame(maxWidth: .infinity)
    }

    private func callout(text: String, sub: String, x: CGFloat, width: CGFloat) -> some View {
        let w: CGFloat = 96
        let clampedX = Swift.min(Swift.max(x - w / 2, 0), Swift.max(width - w, 0))
        return VStack(spacing: 1) {
            Text(text).font(.axDisplay(12, .bold)).foregroundStyle(.axPrimary)
            Text(sub).font(.axMono(9)).foregroundStyle(.axSecondary)
        }
        .frame(width: w)
        .padding(.vertical, 5)
        .background(Color.axSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.axBorder, lineWidth: 1))
        .offset(x: clampedX, y: -6)
        .allowsHitTesting(false)
    }

    // MARK: - Geometry & interaction

    private func points(in size: CGSize) -> [CGPoint] {
        let h = size.height
        let usable = h - vPad * 2
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { i, v in
            let y = vPad + (1 - (v - minVal) / range) * usable
            return CGPoint(x: CGFloat(i) * step, y: y)
        }
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                let step = width / CGFloat(values.count - 1)
                let i = Int((g.location.x / step).rounded())
                selectedIndex = Swift.min(Swift.max(i, 0), values.count - 1)
            }
            .onEnded { _ in selectedIndex = nil }
    }

    // MARK: - Formatters

    private static let dayLabel: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()
    private static let calloutDate: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f
    }()
}
