import SwiftUI

/// A single activity stream (HR / power / speed / elevation / cadence) as a
/// filled line chart (§10). Supports coloured zone bands behind the line (HR
/// zones) and an optional dashed reference line (e.g. FTP).
struct ActivityStreamChart: View {
    let title: String
    let values: [Double]
    let color: Color
    let unit: String
    var zoneBands: [ZoneBand] = []
    var referenceLine: Double? = nil
    var referenceLabel: String? = nil
    /// Seconds from start of the last sample — drives the x-axis duration label.
    var durationSeconds: Double = 0
    /// Seconds-from-start per sample (index-aligned with `values`) — drives the
    /// scrub callout's elapsed time. Falls back to a linear estimate when absent.
    var time: [Double] = []

    @State private var selectedIndex: Int? = nil

    struct ZoneBand: Identifiable {
        let id = UUID()
        let lower: Double
        let upper: Double
        let color: Color
    }

    private var minV: Double { values.min() ?? 0 }
    private var maxV: Double { values.max() ?? 1 }
    private var range: Double { Swift.max(maxV - minV, 0.0001) }
    private var avgV: Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }

    private func frac(_ v: Double) -> Double { Swift.min(Swift.max((v - minV) / range, 0), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title.uppercased())
                    .font(.axMono(10, .semibold)).foregroundStyle(.axTertiary).tracking(1.5)
                Spacer()
                Text("\(Int(minV.rounded()))–\(Int(maxV.rounded())) \(unit)")
                    .font(.axMono(10)).foregroundStyle(.axTertiary)
            }

            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    // Zone bands behind the trace.
                    ForEach(zoneBands) { b in
                        let top = geo.size.height * (1 - frac(Swift.min(b.upper, maxV)))
                        let bottom = geo.size.height * (1 - frac(Swift.max(b.lower, minV)))
                        Rectangle()
                            .fill(b.color.opacity(0.16))
                            .frame(width: geo.size.width, height: Swift.max(0, bottom - top))
                            .offset(y: top)
                    }

                    // Reference line (e.g. FTP).
                    if let ref = referenceLine, ref >= minV, ref <= maxV {
                        let y = geo.size.height * (1 - frac(ref))
                        Rectangle()
                            .fill(color.opacity(0.5))
                            .frame(width: geo.size.width, height: 1)
                            .offset(y: y)
                    }

                    // Series average as a dashed line (dashed keeps it distinct
                    // from the solid reference line above).
                    if values.count > 1 {
                        let yAvg = geo.size.height * (1 - frac(avgV))
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: yAvg))
                            p.addLine(to: CGPoint(x: geo.size.width, y: yAvg))
                        }
                        .stroke(color.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        Text("AVG \(Int(avgV.rounded()))")
                            .font(.axMono(8, .semibold))
                            .foregroundStyle(color.opacity(0.8))
                            .position(x: geo.size.width - 24, y: yAvg < 14 ? yAvg + 9 : yAvg - 7)
                    }

                    let pts = points(in: geo.size)
                    Path { p in
                        p.move(to: CGPoint(x: pts.first?.x ?? 0, y: geo.size.height))
                        pts.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: pts.last?.x ?? 0, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.25), color.opacity(0.02)],
                                         startPoint: .top, endPoint: .bottom))
                    Path { p in
                        guard let first = pts.first else { return }
                        p.move(to: first)
                        pts.dropFirst().forEach { p.addLine(to: $0) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    if let i = selectedIndex, pts.indices.contains(i) {
                        // Scrub indicator: vertical line + marker dot + value/time callout.
                        Rectangle()
                            .fill(color.opacity(0.35))
                            .frame(width: 1, height: geo.size.height)
                            .position(x: pts[i].x, y: geo.size.height / 2)
                        Circle().fill(.white).frame(width: 10, height: 10)
                            .overlay(Circle().stroke(color, lineWidth: 3))
                            .position(pts[i])
                        callout(text: "\(Int(values[i].rounded())) \(unit)",
                                sub: Self.elapsedLabel(elapsedSeconds(at: i)),
                                x: pts[i].x, width: geo.size.width)
                    } else if let last = pts.last {
                        Circle().fill(color).frame(width: 6, height: 6)
                            .shadow(color: color.opacity(0.5), radius: 6)
                            .position(last)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            guard values.count > 1 else { return }
                            let step = geo.size.width / CGFloat(values.count - 1)
                            let i = Int((g.location.x / step).rounded())
                            selectedIndex = Swift.min(Swift.max(i, 0), values.count - 1)
                        }
                        .onEnded { _ in selectedIndex = nil }
                )
            }
            .frame(height: 110)

            HStack {
                Text("0:00")
                Spacer()
                if let ref = referenceLine, let label = referenceLabel {
                    Text("\(label) \(Int(ref.rounded())) \(unit)").foregroundStyle(color.opacity(0.8))
                    Spacer()
                }
                Text(Self.durationLabel(durationSeconds))
            }
            .font(.axMono(9)).foregroundStyle(.axTertiary)
        }
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

    /// Seconds from start at sample `i`: real timestamps when the time stream is
    /// aligned, otherwise a linear estimate across the activity duration.
    private func elapsedSeconds(at i: Int) -> Double {
        if time.count == values.count { return time[i] }
        guard values.count > 1 else { return 0 }
        return durationSeconds * Double(i) / Double(values.count - 1)
    }

    private static func elapsedLabel(_ seconds: Double) -> String {
        let s = Int(seconds)
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let step = size.width / CGFloat(values.count - 1)
        let pad: CGFloat = 6
        let usable = size.height - pad * 2
        return values.enumerated().map { i, v in
            CGPoint(x: CGFloat(i) * step, y: pad + (1 - CGFloat(frac(v))) * usable)
        }
    }

    private static func durationLabel(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        return m >= 60 ? String(format: "%d:%02d", m / 60, m % 60) : "\(m):00"
    }
}
