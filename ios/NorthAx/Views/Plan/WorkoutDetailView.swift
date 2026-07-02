import SwiftUI

/// Full detail for a planned session (§7): header, workout breakdown (effort
/// graph for endurance / exercise list for strength), planned targets, and —
/// when a matching imported workout exists — an actual-vs-planned comparison.
struct WorkoutDetailView: View {
    let match: SessionMatch
    @Environment(AthleteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var marking = false
    @State private var streams: ActivityStreams?

    private var session: PlannedSession { match.session }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    statTiles
                    breakdownSection
                    plannedTargets
                    if let activity = match.activity { actualVsPlanned(activity) }
                    if let streams, hasVisibleStreams(streams) { activityDataSection(streams) }
                    if match.completion != .done { switchSection }
                    if match.completion == .planned || match.completion == .missed { markCompleteButton }
                }
                .padding(20)
            }
            .background(Color.axBackground)
            .navigationTitle(session.domain.rawValue)
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task {
                if match.completion == .done, let id = match.activity?.id {
                    streams = await store.activityStreams(for: id)
                }
            }
        }
    }

    // MARK: - Activity data (§10): time-series charts for a completed workout

    private func activityDataSection(_ s: ActivityStreams) -> some View {
        // Speed / power / elevation / cadence are only meaningful for motion-based
        // sports. For strength (and other stationary work) they're noise, so show
        // heart rate only.
        let showsMotionStreams = motionStreamDomains.contains(session.domain)
        return card("ACTIVITY DATA") {
            VStack(alignment: .leading, spacing: 18) {
                if !s.heartRate.isEmpty {
                    ActivityStreamChart(title: "Heart rate", values: s.heartRate, color: .axRed,
                                        unit: "bpm", zoneBands: hrZoneBands(), durationSeconds: s.durationSeconds)
                }
                if showsMotionStreams, !s.power.isEmpty {
                    ActivityStreamChart(title: "Power", values: s.power, color: .axAccent, unit: "w",
                                        referenceLine: store.thresholds.ftpWatts.map(Double.init),
                                        referenceLabel: "FTP", durationSeconds: s.durationSeconds)
                }
                if showsMotionStreams, !s.velocity.isEmpty {
                    ActivityStreamChart(title: "Speed", values: s.speedKmh, color: .axGreen,
                                        unit: "km/h", durationSeconds: s.durationSeconds)
                }
                if showsMotionStreams, !s.altitude.isEmpty {
                    ActivityStreamChart(title: "Elevation", values: s.altitude, color: .axBlue,
                                        unit: "m", durationSeconds: s.durationSeconds)
                }
                if showsMotionStreams, !s.cadence.isEmpty {
                    ActivityStreamChart(title: "Cadence", values: s.cadence, color: .axPurple,
                                        unit: "rpm", durationSeconds: s.durationSeconds)
                }
                Label("From \(s.source)", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption2).foregroundStyle(.axTertiary)
            }
        }
    }

    /// Sports where speed/power/elevation/cadence streams are meaningful.
    private var motionStreamDomains: Set<TrainingDomain> {
        [.cycling, .running, .swimming, .triathlon]
    }

    /// Whether there's anything worth charting for this session's sport — for
    /// non-motion sports (e.g. strength) only heart rate counts.
    private func hasVisibleStreams(_ s: ActivityStreams) -> Bool {
        motionStreamDomains.contains(session.domain) ? s.hasData : !s.heartRate.isEmpty
    }

    /// HR zone bands as a fraction of the athlete's max HR (no bands if unset).
    private func hrZoneBands() -> [ActivityStreamChart.ZoneBand] {
        guard let maxHr = store.thresholds.maxHr, maxHr > 0 else { return [] }
        let m = Double(maxHr)
        let zones: [(Double, Double, Int)] = [
            (0.50, 0.60, 1),
            (0.60, 0.70, 2),
            (0.70, 0.80, 3),
            (0.80, 0.90, 4),
            (0.90, 1.05, 5),
        ]
        return zones.map { .init(lower: $0.0 * m, upper: $0.1 * m, color: .zone($0.2)) }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            IconTile(systemName: session.domain.icon, color: session.domain.color, size: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.domain.rawValue.uppercased())
                    .font(.axMono(10, .semibold))
                    .tracking(1.4)
                    .foregroundStyle(session.domain.color)
                Text(session.title)
                    .font(.axDisplay(20, .heavy))
                    .tracking(-0.4)
                    .foregroundStyle(.axPrimary)
                Text(dateLabel.uppercased())
                    .font(.axMono(10))
                    .tracking(0.6)
                    .foregroundStyle(.axSecondary)
            }
            Spacer()
            CompletionPill(completion: match.completion)
        }
    }

    // MARK: - Stat tiles (TIME / EFFORT / LOAD)

    private var statTiles: some View {
        let load = store.sessionLoad(durationMin: session.duration, intensity: session.intensityLabel)
        return HStack(spacing: 10) {
            StatTile(label: "Time", value: "\(session.duration) min")
            StatTile(label: "Effort", value: effortShortLabel, valueColor: effortColor)
            StatTile(label: "Load", value: "\(Int(load.rounded()))")
        }
    }

    private var effortShortLabel: String {
        let l = session.intensityLabel.lowercased()
        if l.contains("moderate") { return "MOD" }
        return session.intensityLabel.uppercased()
    }

    private var effortColor: Color {
        let l = session.intensityLabel.lowercased()
        if l.contains("easy") || l.contains("light") || l.contains("recovery") { return .axGreen }
        if l.contains("hard") || l.contains("max") { return .axRed }
        return .axAmber
    }

    // MARK: - Breakdown (exercise list for strength, effort graph for endurance)

    @ViewBuilder
    private var breakdownSection: some View {
        if let exercises = session.exercises, !exercises.isEmpty {
            card("WORKOUT") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(exercises) { ex in
                        HStack(alignment: .top, spacing: 10) {
                            Text(ex.muscleGroup.rawValue.uppercased())
                                .font(.axMono(9, .semibold))
                                .foregroundStyle(ex.muscleGroup.color).tracking(0.5)
                                .frame(width: 64, alignment: .leading).padding(.top, 3)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(ex.name).font(.axDisplay(14, .bold)).foregroundStyle(.axPrimary)
                                    Spacer()
                                    Text(ex.setDisplay).font(.axMono(11, .semibold)).foregroundStyle(.axSecondary)
                                }
                                Text("Rest \(ex.rest)" + (ex.notes.map { " · \($0)" } ?? ""))
                                    .font(.axMono(10)).foregroundStyle(.axTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        } else if let workout = session.workout {
            card("WORKOUT") {
                WorkoutEffortGraphView(workout: workout, sport: session.domain,
                                       cyclingTarget: store.cyclingTarget)
            }
        }
    }

    // MARK: - Planned targets

    private var plannedTargets: some View {
        card("PLANNED") {
            VStack(spacing: 10) {
                targetRow("Duration", "\(session.duration) min")
                targetRow("Intensity", session.intensityLabel)
                if let subtitle = session.subtitle.isEmpty ? nil : session.subtitle {
                    targetRow("Focus", subtitle)
                }
            }
        }
    }

    // MARK: - Actual vs planned

    private func actualVsPlanned(_ a: GarminActivity) -> some View {
        card("ACTUAL vs PLANNED") {
            VStack(spacing: 10) {
                comparisonRow("Duration", planned: "\(session.duration) min", actual: a.formattedDuration)
                comparisonRow("Distance", planned: "—", actual: a.formattedDistance ?? "—")
                comparisonRow("Avg HR", planned: "—", actual: a.avgHeartRate.map { "\($0) bpm" } ?? "—")
                comparisonRow("Load", planned: "—", actual: a.trainingLoad.map { String(format: "%.0f", $0) } ?? "—")
                Rectangle().fill(Color.axBorder).frame(height: 1)
                Label("Matched from intervals.icu", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption2).foregroundStyle(.axTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Switch suggestions (§9): pre-fetched AI alternatives, else fallback

    @ViewBuilder
    private var switchSection: some View {
        let key = match.suggestionKey
        let ai = store.dailySuggestions[key]
        let loading = store.suggestionsLoading.contains(key)
        card("SWITCH TO…") {
            if loading && ai == nil {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small).tint(.axAccent)
                    Text("Finding smart alternatives…").font(.caption).foregroundStyle(.axSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                let list = (ai?.isEmpty == false) ? ai! : store.fallbackSuggestions(excluding: session.domain)
                if list.isEmpty {
                    Text("No alternatives available.").font(.caption).foregroundStyle(.axTertiary)
                } else {
                    VStack(spacing: 10) {
                        ForEach(list) { s in
                            SwitchSuggestionRow(suggestion: s, match: match, onApplied: { dismiss() })
                        }
                    }
                    if !(list.first?.isAI ?? false) {
                        Text("Basic suggestions — smart recommendations aren't available right now.")
                            .font(.caption2).foregroundStyle(.axTertiary)
                            .padding(.top, 2)
                    }
                }
            }
        }
    }

    // MARK: - Mark complete (preserves the HealthKit write path, §4)

    private var markCompleteButton: some View {
        Button {
            marking = true
            Task {
                await store.markSessionDone(domain: session.domain, title: session.title,
                                            durationMin: session.duration)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: marking ? "checkmark" : "checkmark.circle")
                Text(marking ? "Marked complete" : "Mark complete")
            }
            .font(.axDisplay(15, .bold))
            .foregroundStyle(marking ? Color.axBackground : session.domain.color)
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(marking ? Color.axGreen : session.domain.color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .disabled(marking)
    }

    // MARK: - Building blocks

    private func card<Content: View>(_ title: String, @ViewBuilder _ content: @escaping () -> Content) -> some View {
        AxCard(radius: 18, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(title)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func targetRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.axDisplay(13.5)).foregroundStyle(.axSecondary)
            Spacer()
            Text(value).font(.axDisplay(13.5, .semibold)).foregroundStyle(.axPrimary)
        }
    }

    private func comparisonRow(_ label: String, planned: String, actual: String) -> some View {
        HStack {
            Text(label).font(.axDisplay(13.5)).foregroundStyle(.axSecondary)
            Spacer()
            Text(planned).font(.axMono(11)).foregroundStyle(.axTertiary)
                .frame(width: 80, alignment: .trailing)
            Text(actual).font(.axMono(11, .semibold)).foregroundStyle(.axPrimary)
                .frame(width: 80, alignment: .trailing)
        }
    }

    private var dateLabel: String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"
        return f.string(from: match.day.date)
    }
}

// MARK: - Switch suggestion row (expand to see the breakdown, tap to apply)

private struct SwitchSuggestionRow: View {
    @Environment(AthleteStore.self) private var store
    let suggestion: SwitchSuggestion
    let match: SessionMatch
    let onApplied: () -> Void
    @State private var expanded = false
    @State private var applying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.spring(duration: 0.25)) { expanded.toggle() } } label: { header }
                .buttonStyle(.plain)

            if expanded {
                SessionBreakdownView(domain: suggestion.domain, workout: suggestion.workout,
                                     exercises: suggestion.exercises)
                Button(action: apply) {
                    HStack(spacing: 6) {
                        Image(systemName: applying ? "checkmark" : "arrow.left.arrow.right")
                        Text(applying ? "Switching…" : "Use this session")
                    }
                    .font(.axDisplay(14, .bold))
                    .foregroundStyle(Color.axBackground)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(suggestion.domain.color)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(applying)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.axInset)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(systemName: suggestion.domain.icon, color: suggestion.domain.color, size: 34, radius: 8)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(suggestion.title).font(.axDisplay(14, .bold)).foregroundStyle(.axPrimary)
                    Spacer()
                    Text("\(suggestion.duration) MIN").font(.axMono(10)).foregroundStyle(.axSecondary)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundStyle(.axTertiary)
                }
                Text((suggestion.intensityLabel + (suggestion.estimatedLoad.map { " · ~\(Int($0)) load" } ?? "")).uppercased())
                    .font(.axMono(10)).tracking(0.6).foregroundStyle(.axSecondary)
                if let r = suggestion.rationale, !r.isEmpty {
                    Text(r).font(.axDisplay(11.5)).foregroundStyle(.axAccent)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !suggestion.description.isEmpty {
                    Text(suggestion.description).font(.axDisplay(11.5)).foregroundStyle(.axTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func apply() {
        applying = true
        Task {
            await store.applySwitch(for: match, to: suggestion)
            onApplied()
        }
    }
}
