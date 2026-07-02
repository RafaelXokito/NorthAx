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
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(greeting).font(.subheadline).foregroundStyle(.axSecondary)
                Text(store.athleteName).font(.largeTitle.bold()).foregroundStyle(.white)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(weekdayString)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.axTertiary).tracking(1.5)
                Text(dateString).font(.subheadline.weight(.semibold)).foregroundStyle(.axSecondary)
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

    // MARK: - Back-to-this-week pill (§11)

    private var backToThisWeekPill: some View {
        Button {
            withAnimation(.spring(duration: 0.3)) { weekOffset = 0 }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.left").font(.caption2.bold())
                Text("Back to this week").font(.caption.weight(.semibold))
            }
            .foregroundStyle(.axAccent)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Color.axAccent.opacity(0.12))
            .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Today (detailed card below the readiness ring)

    private func todaySection(_ matches: [SessionMatch]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("TODAY")
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
        HStack(spacing: 14) {
            Image(systemName: "moon.stars.fill")
                .font(.title2).foregroundStyle(.axTertiary)
                .frame(width: 48, height: 48)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text("REST DAY")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.axTertiary).tracking(1.2)
                Text("No session planned").font(.headline).foregroundStyle(.white)
                Text("Recovery is training too — rest up for tomorrow.")
                    .font(.caption).foregroundStyle(.axSecondary)
            }
            Spacer()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.axSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.axBorder, lineWidth: 1))
    }

    private func todayCard(_ match: SessionMatch) -> some View {
        let s = match.session
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: s.domain.icon)
                    .font(.title2)
                    .foregroundStyle(s.domain.color)
                    .frame(width: 48, height: 48)
                    .background(s.domain.color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.domain.rawValue.uppercased())
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.axTertiary).tracking(1.2)
                    Text(s.title).font(.headline).foregroundStyle(.white)
                    Text("\(s.duration) min · \(s.intensityLabel)")
                        .font(.caption).foregroundStyle(.axSecondary)
                }
                Spacer()
                completionBadge(match.completion)
            }
            if !s.subtitle.isEmpty {
                Text(s.subtitle).font(.subheadline).foregroundStyle(.axSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SessionBreakdownView(domain: s.domain, workout: s.workout, exercises: s.exercises)
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
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.axAccent.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.axAccent.opacity(0.3), lineWidth: 1))
    }

    private func completionBadge(_ c: SessionCompletion) -> some View {
        HStack(spacing: 5) {
            Image(systemName: c.icon).font(.system(size: 10, weight: .semibold))
            Text(c.label).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(c.color)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(c.color.opacity(0.12))
        .clipShape(Capsule())
    }

    private func actualStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(.axTertiary).tracking(0.5)
            Text(value).font(.system(size: 13, weight: .semibold)).foregroundStyle(.axPrimary)
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

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.axTertiary).tracking(2)
    }

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
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Color.axAccent.opacity(0.12)).frame(width: 76, height: 76)
                Image(systemName: icon)
                    .font(.system(size: 30))
                    .foregroundStyle(.axAccent)
            }

            VStack(spacing: 8) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.subheadline)
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
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.axAccent)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Color.axSurface)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.axBorder, lineWidth: 1))
    }
}

#Preview {
    DashboardView()
        .environment(AthleteStore())
}
