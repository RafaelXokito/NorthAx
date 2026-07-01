import SwiftUI

/// Full detail for a planned session (§7): header, workout breakdown (effort
/// graph for endurance / exercise list for strength), planned targets, and —
/// when a matching imported workout exists — an actual-vs-planned comparison.
struct WorkoutDetailView: View {
    let match: SessionMatch
    @Environment(AthleteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var marking = false

    private var session: PlannedSession { match.session }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    breakdownSection
                    plannedTargets
                    if let activity = match.activity { actualVsPlanned(activity) }
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
        }
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
