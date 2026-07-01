import SwiftUI

/// Plan-centric main screen (§7 + §8): a compact tap-for-detail readiness ring,
/// the week-at-a-glance strip, and the week's session cards with live completion
/// state matched against imported workouts. Session detail and the readiness
/// breakdown both open as sheets.
struct DashboardView: View {
    @Environment(AthleteStore.self) private var store
    @State private var showReadinessDetail = false
    @State private var selectedMatch: SessionMatch?

    var body: some View {
        ZStack {
            Color.axBackground.ignoresSafeArea(edges: .top)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        headerSection

                        if let readiness = store.readiness {
                            compactReadiness(readiness)
                        }

                        if let week = store.currentWeek {
                            let matches = store.currentWeekMatches
                            WeekGlanceView(week: week, matches: matches) { date in
                                if let target = matches.first(where: { $0.day.date == date }) {
                                    withAnimation(.spring(duration: 0.35)) {
                                        proxy.scrollTo(target.id, anchor: .top)
                                    }
                                }
                            }
                            planSection(matches)
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
            VStack(spacing: 10) {
                ReadinessRingView(score: r.score, status: r.status)
                    .frame(width: 150, height: 150)
                Text(r.status.rawValue)
                    .font(.headline)
                    .foregroundStyle(r.status.ringColor)
                HStack(spacing: 4) {
                    Text("Tap to see why").font(.caption)
                    Image(systemName: "chevron.right").font(.caption2)
                }
                .foregroundStyle(.axTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(Color.axSurface)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.axBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Plan (session cards)

    private func planSection(_ matches: [SessionMatch]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader((store.currentWeek?.isCurrentWeek ?? false) ? "THIS WEEK" : "PLANNED")
            if matches.isEmpty {
                Text("No sessions scheduled this week.")
                    .font(.subheadline)
                    .foregroundStyle(.axTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 10) {
                    ForEach(matches) { match in
                        Button { selectedMatch = match } label: { sessionCard(match) }
                            .buttonStyle(.plain)
                            .id(match.id)
                    }
                }
            }
        }
    }

    private func sessionCard(_ match: SessionMatch) -> some View {
        let session = match.session
        let past = match.completion == .missed || match.completion == .done
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: session.domain.icon)
                    .font(.title3)
                    .foregroundStyle(past ? .axTertiary : session.domain.color)
                    .frame(width: 44, height: 44)
                    .background((past ? Color.white : session.domain.color).opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("\(dayLabel(match.day)) · \(session.duration) min · \(session.intensityLabel)")
                        .font(.caption)
                        .foregroundStyle(.axSecondary)
                }
                Spacer()
                completionBadge(match.completion)
            }

            // Actual stats when a matching workout was found.
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
        .padding(16)
        .background(match.day.isToday ? Color.axAccent.opacity(0.06) : Color.axSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(
            match.day.isToday ? Color.axAccent.opacity(0.3) : Color.axBorder, lineWidth: 1))
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

    private func dayLabel(_ day: PlannedDay) -> String {
        if day.isToday { return "Today" }
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        if Calendar.current.isDate(day.date, inSameDayAs: tomorrow) { return "Tomorrow" }
        return day.weekdayShort
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
