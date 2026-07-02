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
        let zones: [(Double, Double, Color)] = [
            (0.50, 0.60, .axBlue),
            (0.60, 0.70, .axGreen),
            (0.70, 0.80, .axAccent),
            (0.80, 0.90, Color(red: 1.0, green: 0.45, blue: 0.2)),
            (0.90, 1.05, .axRed),
        ]
        return zones.map { .init(lower: $0.0 * m, upper: $0.1 * m, color: $0.2) }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: session.domain.icon)
                .font(.title2)
                .foregroundStyle(session.domain.color)
                .frame(width: 52, height: 52)
                .background(session.domain.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text(dateLabel)
                    .font(.subheadline)
                    .foregroundStyle(.axSecondary)
            }
            Spacer()
            completionBadge
        }
    }

    private var completionBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: match.completion.icon).font(.system(size: 11, weight: .semibold))
            Text(match.completion.label).font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(match.completion.color)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(match.completion.color.opacity(0.12))
        .clipShape(Capsule())
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
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.axAccent).tracking(0.5)
                                .frame(width: 64, alignment: .leading).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(ex.name).font(.caption.weight(.semibold)).foregroundStyle(.axPrimary)
                                    Spacer()
                                    Text(ex.setDisplay).font(.caption2.weight(.semibold)).foregroundStyle(.axSecondary)
                                }
                                Text("Rest \(ex.rest)" + (ex.notes.map { " · \($0)" } ?? ""))
                                    .font(.caption2).foregroundStyle(.axTertiary)
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
            .font(.headline)
            .foregroundStyle(marking ? Color.black : session.domain.color)
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(marking ? Color.axGreen : session.domain.color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(marking)
    }

    // MARK: - Building blocks

    private func card<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.axTertiary).tracking(2)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.axSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.axBorder, lineWidth: 1))
    }

    private func targetRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.axSecondary)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
        }
    }

    private func comparisonRow(_ label: String, planned: String, actual: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.axSecondary)
            Spacer()
            Text(planned).font(.caption.weight(.medium)).foregroundStyle(.axTertiary)
                .frame(width: 80, alignment: .trailing)
            Text(actual).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
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
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(suggestion.domain.color)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(applying)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: suggestion.domain.icon)
                .font(.subheadline).foregroundStyle(suggestion.domain.color)
                .frame(width: 34, height: 34)
                .background(suggestion.domain.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(suggestion.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Spacer()
                    Text("\(suggestion.duration) min").font(.caption).foregroundStyle(.axSecondary)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundStyle(.axTertiary)
                }
                Text(suggestion.intensityLabel + (suggestion.estimatedLoad.map { " · ~\(Int($0)) load" } ?? ""))
                    .font(.caption).foregroundStyle(.axSecondary)
                if let r = suggestion.rationale, !r.isEmpty {
                    Text(r).font(.caption2).foregroundStyle(.axAccent)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !suggestion.description.isEmpty {
                    Text(suggestion.description).font(.caption2).foregroundStyle(.axTertiary)
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
