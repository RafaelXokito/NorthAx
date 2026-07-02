import SwiftUI

/// Plan-centric main screen (§7 + §8): a compact tap-for-detail readiness ring,
/// the week-at-a-glance strip, and the week's session cards with live completion
/// state matched against imported workouts. Session detail and the readiness
/// breakdown both open as sheets.
struct DashboardView: View {
    @Environment(AthleteStore.self) private var store
    @State private var showReadinessDetail = false
    @State private var selectedMatch: SessionMatch?
    @State private var weekOffset = 0

    var body: some View {
        ZStack {
            Color.axBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    headerSection

                    if let readiness = store.readiness {
                        compactReadiness(readiness)
                    }

                    if store.currentWeek != nil, let data = store.weekData(offset: weekOffset) {
                        // Today's session always reflects today — independent of the
                        // week being browsed in the strip below.
                        todaySection(store.currentWeekMatches.filter { $0.day.isToday })
                        WeekGlanceView(week: data.week, matches: data.matches,
                                       offset: $weekOffset, maxForward: store.maxFutureWeekOffset) { date in
                            if let m = data.matches.first(where: { $0.day.date == date }) { selectedMatch = m }
                        }
                        if weekOffset != 0 { backToThisWeekPill }
                    }

                    if !store.goalChecks.isEmpty {
                        goalCheckSection
                    }

                    if store.readiness == nil && store.currentWeek == nil {
                        noDataSection
                    }
#if DEBUG
                    if store.isDebugSession { debugToggle }
#endif
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 48)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $showReadinessDetail) {
            if let readiness = store.readiness {
                ReadinessDetailView(readiness: readiness)
            }
        }
        .sheet(item: $selectedMatch) { WorkoutDetailView(match: $0) }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(weekdayString) · \(dateString.uppercased())")
                .font(.axMono(10, .semibold))
                .tracking(1.8)
                .foregroundStyle(.axTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting).font(.axDisplay(15)).foregroundStyle(.axSecondary)
                Text(store.athleteName)
                    .font(.axDisplay(30, .heavy))
                    .tracking(-0.9)
                    .foregroundStyle(.axPrimary)
            }
        }
    }

    // MARK: - Compact readiness (tap → detail sheet)

    private func compactReadiness(_ r: DailyReadiness) -> some View {
        Button { showReadinessDetail = true } label: {
            AxCard(radius: 24, padding: 20) {
                VStack(spacing: 16) {
                    ReadinessRingView(score: r.score, status: r.status)
                        .frame(width: 220, height: 220)

                    AxPill(text: r.status.rawValue, color: r.status.color)

                    VStack(spacing: 10) {
                        ContributorMeter(label: "HRV", value: hrvMeterValue(r), score: r.hrvScore, color: .axGreen)
                        ContributorMeter(label: "Sleep", value: sleepMeterValue(r), score: r.sleepScore, color: .axPurple)
                        ContributorMeter(label: "Load", value: "\(r.loadScore)", score: r.loadScore, color: .axAccent)
                    }

                    HStack(spacing: 6) {
                        Text("SEE FULL BREAKDOWN")
                            .font(.axMono(10, .semibold))
                            .tracking(1.2)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(.axAccent)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
    }

    private func hrvMeterValue(_ r: DailyReadiness) -> String {
        if let m = store.metrics { return "\(Int(m.hrv)) MS" }
        return "\(r.hrvScore)"
    }

    private func sleepMeterValue(_ r: DailyReadiness) -> String {
        if let m = store.metrics { return String(format: "%.1f H", m.sleepDuration) }
        return "\(r.sleepScore)"
    }

    // MARK: - Goal check (post-sync AI target progress)

    private var goalCheckSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("GOAL CHECK")
            ForEach(store.goalChecks) { check in
                GoalCheckCard(check: check) {
                    Task { await store.applyPlanChanges() }
                }
            }
        }
    }

    // MARK: - Back-to-this-week pill (§11)

    private var backToThisWeekPill: some View {
        Button {
            withAnimation(.spring(duration: 0.3)) { weekOffset = 0 }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.left").font(.system(size: 9, weight: .bold))
                Text("BACK TO THIS WEEK").font(.axMono(10, .semibold)).tracking(1)
            }
            .foregroundStyle(.axAccent)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Color.axAccent.opacity(0.14))
            .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Today (detailed card below the readiness ring)

    private func todaySection(_ matches: [SessionMatch]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("TODAY'S SESSION")
            if matches.isEmpty {
                todayRestCard
            } else {
                VStack(spacing: 10) {
                    ForEach(matches) { m in
                        todayCard(m)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedMatch = m }
                    }
                }
            }
        }
    }

    // Shown when today has no planned session — a rest day still gets a card.
    private var todayRestCard: some View {
        AxCard {
            HStack(spacing: 14) {
                IconTile(systemName: "moon.stars.fill", color: .axTertiary, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("REST DAY")
                        .font(.axMono(10, .semibold)).foregroundStyle(.axTertiary).tracking(1.4)
                    Text("No session planned").font(.axDisplay(16, .bold)).foregroundStyle(.axPrimary)
                    Text("Recovery is training too — rest up for tomorrow.")
                        .font(.axDisplay(12.5)).foregroundStyle(.axSecondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func todayCard(_ match: SessionMatch) -> some View {
        let s = match.session
        return AxCard(highlighted: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(s.domain.rawValue.uppercased())
                            .font(.axMono(10, .semibold)).foregroundStyle(s.domain.color).tracking(1.8)
                        Text(s.title)
                            .font(.axDisplay(22, .heavy))
                            .tracking(-0.44)
                            .foregroundStyle(.axPrimary)
                        Text(todayMetaLine(s))
                            .font(.axMono(10)).tracking(1.2).foregroundStyle(.axSecondary)
                    }
                    Spacer()
                    CompletionPill(completion: match.completion)
                }
                if !s.subtitle.isEmpty {
                    Text(s.subtitle).font(.axDisplay(13.5)).foregroundStyle(.axSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let exercises = s.exercises, !exercises.isEmpty {
                    exercisePreview(exercises)
                } else {
                    SessionBreakdownView(domain: s.domain, workout: s.workout, exercises: nil)
                    Rectangle().fill(Color.axBorder).frame(height: 1)
                    HStack {
                        Spacer()
                        viewWorkoutLink
                    }
                }

                if let a = match.activity {
                    Rectangle().fill(Color.axBorder).frame(height: 1)
                    HStack(spacing: 16) {
                        actualStat("Time", a.formattedDuration)
                        if let dist = a.formattedDistance { actualStat("Dist", dist) }
                        if let hr = a.avgHeartRate { actualStat("Avg HR", "\(hr)") }
                        if let load = a.trainingLoad { actualStat("Load", String(format: "%.0f", load)) }
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func todayMetaLine(_ s: PlannedSession) -> String {
        var line = "\(s.duration) MIN · \(s.intensityLabel.uppercased())"
        if let n = s.exercises?.count, n > 0 { line += " · \(n) MOVES" }
        return line
    }

    // First three moves + a "+N more / view workout" footer, per the design.
    private func exercisePreview(_ exercises: [ExerciseSuggestion]) -> some View {
        let preview = Array(exercises.prefix(3))
        return VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Color.axBorder).frame(height: 1)
            ForEach(preview) { ex in
                HStack(spacing: 12) {
                    Text(ex.muscleGroup.rawValue.uppercased())
                        .font(.axMono(10, .semibold))
                        .tracking(0.8)
                        .foregroundStyle(ex.muscleGroup.color)
                        .frame(width: 64, alignment: .leading)
                    Text(ex.name)
                        .font(.axDisplay(15, .bold))
                        .foregroundStyle(.axPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(ex.setDisplay)
                        .font(.axMono(12))
                        .foregroundStyle(.axSecondary)
                }
                .padding(.vertical, 12)
                Rectangle().fill(Color.axBorder).frame(height: 1)
            }
            HStack {
                if exercises.count > 3 {
                    Text("+\(exercises.count - 3) MORE MOVES")
                        .font(.axMono(10))
                        .tracking(1.2)
                        .foregroundStyle(.axTertiary)
                }
                Spacer()
                viewWorkoutLink
            }
            .padding(.top, 12)
        }
    }

    private var viewWorkoutLink: some View {
        HStack(spacing: 6) {
            Text("VIEW WORKOUT")
                .font(.axMono(10, .semibold))
                .tracking(1.2)
            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(.axAccent)
    }

    private func actualStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.axMono(9, .semibold)).foregroundStyle(.axTertiary).tracking(0.8)
            Text(value).font(.axDisplay(13, .bold)).foregroundStyle(.axPrimary)
        }
    }

    // MARK: - No data

    private var noDataSection: some View {
        NoDataView(
            icon: "waveform.path.ecg",
            title: "No training data yet",
            message: "Connect a data source to see your daily readiness, and set up a plan to track your training week. There's nothing to show until then.",
            actionTitle: "Enable integrations"
        ) {
            store.selectedTab = .settings
        }
        .padding(.top, 8)
    }

#if DEBUG
    private var debugToggle: some View {
        @Bindable var bindable = store
        return Toggle("Simulate fatigue", isOn: $bindable.useFatiguedScenario)
            .font(.caption).foregroundStyle(.axTertiary).tint(.axRed).padding(.horizontal, 4)
    }
#endif

    // MARK: - Helpers

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 12 { return "Good morning," }
        if h < 17 { return "Good afternoon," }
        return "Good evening,"
    }

    private var weekdayString: String {
        let f = DateFormatter(); f.dateFormat = "EEEE"
        return f.string(from: Date()).uppercased()
    }

    private var dateString: String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: Date())
    }
}

// MARK: - Reusable empty state

/// Shown wherever live data is absent. Offers a single CTA that deep-links to
/// Settings so the user can connect a data source. Used by Dashboard + Metrics.
struct NoDataView: View {
    var icon: String = "antenna.radiowaves.left.and.right"
    var title: String
    var message: String
    var actionTitle: String = "Enable integrations"
    var action: () -> Void

    var body: some View {
        AxCard(radius: 24, padding: 28) {
            VStack(spacing: 18) {
                ZStack {
                    Circle().fill(Color.axAccent.opacity(0.14)).frame(width: 76, height: 76)
                    Image(systemName: icon)
                        .font(.system(size: 30))
                        .foregroundStyle(.axAccent)
                }

                VStack(spacing: 8) {
                    Text(title)
                        .font(.axDisplay(18, .bold))
                        .foregroundStyle(.axPrimary)
                        .multilineTextAlignment(.center)
                    Text(message)
                        .font(.axDisplay(13.5))
                        .foregroundStyle(.axSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: action) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text(actionTitle)
                    }
                    .font(.axDisplay(15, .bold))
                    .foregroundStyle(Color.axBackground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.axAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    DashboardView()
        .environment(AthleteStore())
}
