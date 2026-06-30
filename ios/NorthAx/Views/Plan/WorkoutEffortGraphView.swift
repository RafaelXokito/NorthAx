import SwiftUI

// Horizontal stepped-area chart of a structured workout. X axis = elapsed
// minutes, each segment scaled by duration and colored by training zone.
// Warm-up / cool-down steps render as sloped ramps. When athlete thresholds
// are present (via the store) the Y axis becomes a real numeric scale
// (bpm / watts / pace) and labels carry concrete ranges; otherwise it falls
// back to zone-fraction heights and zone-only labels — never inventing numbers.

struct WorkoutEffortGraphView: View {
    let workout: StructuredWorkoutDTO
    let sport: TrainingDomain
    let cyclingTarget: String   // "hr" | "power" — only relevant for cycling

    @Environment(AthleteStore.self) private var store

    @State private var selected: EffortSegment?

    // Flattened timeline: each `repeat` is expanded so widths reflect real minutes.
    private var segments: [EffortSegment] {
        var out: [EffortSegment] = []
        for block in workout.blocks {
            let reps = max(block.repeat, 1)
            for _ in 0..<reps {
                for step in block.steps where step.minutes > 0 {
                    out.append(EffortSegment(step: step))
                }
            }
        }
        return out
    }

    private var totalMinutes: Int { segments.reduce(0) { $0 + $1.step.minutes } }

    // Intensity metric for this sport/preference.
    private var mode: ZoneMode {
        switch sport {
        case .running, .swimming: return .pace
        case .cycling:            return cyclingTarget == "power" ? .power : .hr
        default:                  return .hr
        }
    }

    // Per-zone midpoint value, when thresholds resolve. nil => zone-fraction fallback.
    private func value(_ zone: EffortZone) -> Double? {
        guard zone.rawValue >= 1 else { return nil }
        return ZoneMath.midpoint(zone: zone.rawValue, mode: mode, sport: sport,
                                 thresholds: store.thresholds)
    }

    // The numeric Y scale (max axis value) when all plotted zones resolve.
    private var axisMax: Double? {
        let vals = segments.compactMap { value($0.zone) }
        guard !vals.isEmpty, vals.count == segments.filter({ $0.zone.rawValue >= 1 }).count,
              let m = vals.max() else { return nil }
        // Pace is inverted (lower seconds = harder); plot inverse so harder = taller.
        return mode == .pace ? 1.0 / m : m * 1.12   // headroom for HR/power
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(metricAxisLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.axTertiary)
                    .tracking(1.5)
                Spacer()
                Text("\(totalMinutes) min")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.axTertiary)
            }

            if segments.isEmpty {
                Text("No structured steps")
                    .font(.caption)
                    .foregroundStyle(.axTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                timeline
                distributionRow
                if let selected { detailRow(selected) }
            }
        }
    }

    // MARK: - Timeline (stepped area + ramps)

    private var timeline: some View {
        HStack(alignment: .bottom, spacing: 6) {
            yAxisLabels
            GeometryReader { geo in
                let total = max(totalMinutes, 1)
                let h = geo.size.height
                ZStack(alignment: .bottomLeading) {
                    gridLines(h: h)
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(Array(segments.enumerated()), id: \.element.id) { _, seg in
                            let w = max(geo.size.width * CGFloat(seg.step.minutes) / CGFloat(total), 2)
                            segmentShape(seg, width: w, height: h)
                                .onTapGesture {
                                    withAnimation(.spring(duration: 0.25)) {
                                        selected = (selected?.id == seg.id) ? nil : seg
                                    }
                                }
                        }
                    }
                }
            }
            .frame(height: 72)
        }
    }

    // One segment: a sloped trapezoid for warm-up/cool-down, else a flat block.
    private func segmentShape(_ seg: EffortSegment, width: CGFloat, height: CGFloat) -> some View {
        let peak = barFraction(seg.zone)
        let base = barFraction(.z1)
        let isSel = selected?.id == seg.id
        let edges: (CGFloat, CGFloat)
        switch seg.ramp {
        case .up:   edges = (base, peak)
        case .down: edges = (peak, base)
        case .none: edges = (peak, peak)
        }
        let topLeft = edges.0
        let topRight = edges.1
        return TrapezoidBar(leftFrac: topLeft, rightFrac: topRight)
            .fill(seg.zone.color.opacity(isSel ? 1.0 : 0.85))
            .overlay(
                TrapezoidBar(leftFrac: topLeft, rightFrac: topRight)
                    .stroke(.white.opacity(isSel ? 0.6 : 0), lineWidth: 1)
            )
            .frame(width: width, height: height)
    }

    // Height fraction for a zone: real value scale when available, else zone steps.
    private func barFraction(_ zone: EffortZone) -> CGFloat {
        guard let axisMax, let v = value(zone) else { return zone.heightFraction }
        let plotted = mode == .pace ? 1.0 / v : v
        return CGFloat(min(max(plotted / axisMax, 0.06), 1.0))
    }

    // MARK: - Axis decoration

    private var yAxisLabels: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if let labels = axisTickLabels {
                ForEach(labels, id: \.self) { t in
                    Text(t).font(.system(size: 9))
                        .foregroundStyle(.axTertiary)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .frame(width: axisTickLabels == nil ? 0 : 30, height: 72)
        .opacity(axisTickLabels == nil ? 0 : 1)
    }

    // Two ticks (top + mid) in real units, when the numeric scale resolves.
    private var axisTickLabels: [String]? {
        guard let axisMax else { return nil }
        func label(_ frac: Double) -> String {
            let plotted = axisMax * frac
            let v = mode == .pace ? 1.0 / plotted : plotted
            let r = ZoneRange(lower: v, upper: v)
            return ZoneMath.format(r, mode: mode, sport: sport, paceUnit: store.thresholds.paceUnit)
                .components(separatedBy: "–").last ?? ""
        }
        return [label(1.0), label(0.5)]
    }

    private func gridLines(h: CGFloat) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.axBorder.opacity(0.4)).frame(height: 0.5)
            Spacer()
            Rectangle().fill(Color.axBorder.opacity(0.4)).frame(height: 0.5)
            Spacer()
        }
        .frame(height: h)
        .opacity(axisMax == nil ? 0 : 1)
    }

    // MARK: - Zone distribution

    private var distributionRow: some View {
        let totals = zoneTotals
        let total = max(totalMinutes, 1)
        return HStack(spacing: 8) {
            ForEach(totals, id: \.zone) { item in
                HStack(spacing: 4) {
                    Circle().fill(item.zone.color).frame(width: 6, height: 6)
                    Text("\(item.zone.shortLabel) \(item.minutes * 100 / total)%")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.axTertiary)
                }
            }
            Spacer()
        }
    }

    private var zoneTotals: [(zone: EffortZone, minutes: Int)] {
        var dict: [Int: Int] = [:]
        for seg in segments { dict[seg.zone.rawValue, default: 0] += seg.step.minutes }
        return dict.sorted { $0.key < $1.key }
            .compactMap { k, v in EffortZone(rawValue: k).map { ($0, v) } }
    }

    // MARK: - Tapped block detail

    private func detailRow(_ seg: EffortSegment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(seg.zone.color).frame(width: 8, height: 8)
                Text(seg.step.cue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.axPrimary)
                Spacer()
                Text("\(seg.step.minutes) min")
                    .font(.caption2)
                    .foregroundStyle(.axSecondary)
            }
            Text(blockLabel(seg))
                .font(.caption2)
                .foregroundStyle(.axSecondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Labels

    private var metricAxisLabel: String {
        switch sport {
        case .running:  return "PACE (MIN/KM)"
        case .swimming: return "PACE (MIN/100M)"
        case .cycling:  return cyclingTarget == "power" ? "POWER" : "HEART RATE"
        default:        return "EFFORT"
        }
    }

    private var modeUnitLabel: String {
        switch mode {
        case .hr: return "HR"; case .power: return "Power"; case .pace: return "Pace"
        }
    }

    // Per-block label: zone token + concrete numeric range when thresholds resolve,
    // else the existing human `target` text. Never invents numbers.
    private func blockLabel(_ seg: EffortSegment) -> String {
        let token = seg.step.icu.isEmpty ? seg.step.target : seg.step.icu
        if seg.zone.rawValue >= 1,
           let r = ZoneMath.range(zone: seg.zone.rawValue, mode: mode, sport: sport,
                                  thresholds: store.thresholds) {
            let nums = ZoneMath.format(r, mode: mode, sport: sport,
                                       paceUnit: store.thresholds.paceUnit)
            return "\(seg.zone.shortLabel) \(modeUnitLabel) · \(nums)"
        }
        return token.isEmpty ? "Steady effort" : token
    }
}

// MARK: - Trapezoid shape (flat block when both fractions equal)

private struct TrapezoidBar: Shape {
    let leftFrac: CGFloat   // top-edge height fraction at left
    let rightFrac: CGFloat  // … at right

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let topL = rect.maxY - rect.height * leftFrac
        let topR = rect.maxY - rect.height * rightFrac
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: topL))
        p.addLine(to: CGPoint(x: rect.maxX, y: topR))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Segment + zone model

private enum Ramp { case none, up, down }

private struct EffortSegment: Identifiable {
    let id = UUID()
    let step: WorkoutStepDTO

    var zone: EffortZone { EffortZone(token: step.icu.isEmpty ? step.target : step.icu) }

    // Ramp detection from the cue text.
    var ramp: Ramp {
        let cue = step.cue.lowercased()
        if cue.contains("warm") { return .up }
        if cue.contains("cool") { return .down }
        return .none
    }
}

private enum EffortZone: Int {
    case neutral = 0, z1 = 1, z2, z3, z4, z5

    init(token: String) {
        let upper = token.uppercased()
        for n in 1...5 where upper.contains("Z\(n)") {
            self = EffortZone(rawValue: n) ?? .neutral
            return
        }
        self = .neutral
    }

    var shortLabel: String { self == .neutral ? "—" : "Z\(rawValue)" }

    // Fallback height when no numeric scale is available.
    var heightFraction: CGFloat {
        switch self {
        case .neutral: return 0.30
        case .z1:      return 0.35
        case .z2:      return 0.50
        case .z3:      return 0.65
        case .z4:      return 0.82
        case .z5:      return 1.00
        }
    }

    var color: Color {
        switch self {
        case .neutral: return .axTertiary
        case .z1:      return .axBlue
        case .z2:      return .axGreen
        case .z3:      return .axAccent
        case .z4:      return Color(red: 1.0, green: 0.45, blue: 0.2)
        case .z5:      return .axRed
        }
    }
}

#Preview {
    let sample = StructuredWorkoutDTO(
        targetMode: "hr",
        blocks: [
            WorkoutBlockDTO(repeat: 1, steps: [
                WorkoutStepDTO(cue: "Warm up", minutes: 10, target: "Z1 easy (HR)", icu: "Z1 HR")
            ]),
            WorkoutBlockDTO(repeat: 4, steps: [
                WorkoutStepDTO(cue: "Work", minutes: 4, target: "Z4 threshold (HR)", icu: "Z4 HR"),
                WorkoutStepDTO(cue: "Recover", minutes: 2, target: "Z2 endurance (HR)", icu: "Z2 HR")
            ]),
            WorkoutBlockDTO(repeat: 1, steps: [
                WorkoutStepDTO(cue: "Cool down", minutes: 8, target: "Z1 easy (HR)", icu: "Z1 HR")
            ])
        ]
    )
    let store = AthleteStore()
    store.thresholds = AthleteThresholds(thresholdHr: 165, maxHr: 188)
    return WorkoutEffortGraphView(workout: sample, sport: .cycling, cyclingTarget: "hr")
        .padding()
        .background(Color.axBackground)
        .environment(store)
}
