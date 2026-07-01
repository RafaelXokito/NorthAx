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
                        // Form band (area between fitness and fatigue).
                        Path { p in
                            guard let f = ctlPts.first else { return }
                            p.move(to: f)
                            ctlPts.dropFirst().forEach { p.addLine(to: $0) }
                            atlPts.reversed().forEach { p.addLine(to: $0) }
                            p.closeSubpath()
                        }
                        .fill(Color.axAccent.opacity(0.10))

                        line(ctlPts, color: .axGreen)
                        line(atlPts, color: Color(red: 1.0, green: 0.55, blue: 0.2))
                    }
                }
                .frame(height: 140)
                HStack {
                    Text(Self.day.string(from: dates.first ?? Date()))
                    Spacer()
                    Text(Self.day.string(from: dates.last ?? Date()))
                }
                .font(.caption2).foregroundStyle(.axTertiary)
            }
        }
    }

    private var legend: some View {
        let form = (ctl.last ?? 0) - (atl.last ?? 0)
        return HStack(spacing: 14) {
            legendItem(.axGreen, "Fitness", ctl.last ?? 0)
            legendItem(Color(red: 1.0, green: 0.55, blue: 0.2), "Fatigue", atl.last ?? 0)
            HStack(spacing: 5) {
                Circle().fill(Color.axAccent).frame(width: 7, height: 7)
                Text("Form").font(.caption2).foregroundStyle(.axTertiary)
                Text("\(form >= 0 ? "+" : "")\(Int(form.rounded()))")
                    .font(.caption.weight(.semibold)).foregroundStyle(.axPrimary)
            }
            Spacer()
        }
    }

    private func legendItem(_ color: Color, _ label: String, _ value: Double) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption2).foregroundStyle(.axTertiary)
            Text("\(Int(value.rounded()))").font(.caption.weight(.semibold)).foregroundStyle(.axPrimary)
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
