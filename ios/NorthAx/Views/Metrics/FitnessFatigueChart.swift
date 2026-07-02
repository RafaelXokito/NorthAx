import SwiftUI

/// Fitness (CTL) vs Fatigue (ATL) over time, with the gap between them shaded as
/// Form (TSB) — the intervals.icu training-load model (§12).
struct FitnessFatigueChart: View {
    let ctl: [Double]   // fitness (chronic load)
    let atl: [Double]   // fatigue (acute load)
    let dates: [Date]

    private var n: Int { Swift.min(ctl.count, atl.count) }
    private var maxV: Double { Swift.max((ctl + atl).max() ?? 1, 1) }

    var body: some View {
        if n < 2 {
            Text("Not enough history yet")
                .font(.footnote).foregroundStyle(.axTertiary)
                .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                legend
                GeometryReader { geo in
                    let ctlPts = points(ctl, in: geo.size)
                    let atlPts = points(atl, in: geo.size)
                    ZStack {
                        // Gradient fill under the fatigue line.
                        Path { p in
                            guard let f = atlPts.first, let l = atlPts.last else { return }
                            p.move(to: CGPoint(x: f.x, y: geo.size.height))
                            atlPts.forEach { p.addLine(to: $0) }
                            p.addLine(to: CGPoint(x: l.x, y: geo.size.height))
                            p.closeSubpath()
                        }
                        .fill(
                            LinearGradient(
                                colors: [Color.axAccent.opacity(0.22), Color.axAccent.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )

                        line(ctlPts, color: .axGreen)
                        line(atlPts, color: .axAccent)

                        if let last = ctlPts.last {
                            Circle().fill(Color.axGreen).frame(width: 6, height: 6)
                                .shadow(color: Color.axGreen.opacity(0.5), radius: 6)
                                .position(last)
                        }
                        if let last = atlPts.last {
                            Circle().fill(Color.axAccent).frame(width: 6, height: 6)
                                .shadow(color: Color.axAccent.opacity(0.5), radius: 6)
                                .position(last)
                        }
                    }
                }
                .frame(height: 140)
                HStack {
                    Text(Self.day.string(from: dates.first ?? Date()).uppercased())
                    Spacer()
                    Text(Self.day.string(from: dates.last ?? Date()).uppercased())
                }
                .font(.axMono(9)).tracking(0.6).foregroundStyle(.axTertiary)
            }
        }
    }

    private var legend: some View {
        let form = (ctl.last ?? 0) - (atl.last ?? 0)
        return HStack(spacing: 14) {
            legendItem(.axGreen, "Fitness", ctl.last ?? 0)
            legendItem(.axAccent, "Fatigue", atl.last ?? 0)
            HStack(spacing: 5) {
                Circle().fill(Color.axAmber).frame(width: 7, height: 7)
                Text("FORM").font(.axMono(9, .semibold)).tracking(0.8).foregroundStyle(.axTertiary)
                Text("\(form >= 0 ? "+" : "")\(Int(form.rounded()))")
                    .font(.axDisplay(12, .bold)).foregroundStyle(.axPrimary)
            }
            Spacer()
        }
    }

    private func legendItem(_ color: Color, _ label: String, _ value: Double) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label.uppercased()).font(.axMono(9, .semibold)).tracking(0.8).foregroundStyle(.axTertiary)
            Text("\(Int(value.rounded()))").font(.axDisplay(12, .bold)).foregroundStyle(.axPrimary)
        }
    }

    private func line(_ pts: [CGPoint], color: Color) -> some View {
        Path { p in
            guard let f = pts.first else { return }
            p.move(to: f)
            pts.dropFirst().forEach { p.addLine(to: $0) }
        }
        .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    private func points(_ values: [Double], in size: CGSize) -> [CGPoint] {
        let vals = Array(values.suffix(n))
        guard vals.count > 1 else { return [] }
        let step = size.width / CGFloat(vals.count - 1)
        let pad: CGFloat = 6
        let usable = size.height - pad * 2
        return vals.enumerated().map { i, v in
            CGPoint(x: CGFloat(i) * step, y: pad + (1 - CGFloat(v / maxV)) * usable)
        }
    }

    private static let day: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()
}
