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

    struct ZoneBand: Identifiable {
        let id = UUID()
        let lower: Double
        let upper: Double
        let color: Color
    }

    private var minV: Double { values.min() ?? 0 }
    private var maxV: Double { values.max() ?? 1 }
    private var range: Double { Swift.max(maxV - minV, 0.0001) }

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

                    if let last = pts.last {
                        Circle().fill(color).frame(width: 6, height: 6)
                            .shadow(color: color.opacity(0.5), radius: 6)
                            .position(last)
                    }
                }
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
