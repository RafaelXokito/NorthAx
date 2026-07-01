import SwiftUI

struct PlanView: View {
    @Environment(AthleteStore.self) private var store
    @State private var selectedWeekIndex: Int = 0
    @State private var showPlanSetup = false
    @State private var selectedMatch: SessionMatch?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if store.weeklyPlans.isEmpty {
                    noPlanState
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                } else {
                    VStack(spacing: 20) {
                        if store.planWasRecentlyUpdated { planUpdatedBanner }
                        weekPicker
                        if let week = currentWeek {
                            let matches = selectedWeekMatches
                            WeekGlanceView(week: week, matches: matches) { date in
                                if let target = matches.first(where: { $0.day.date == date }) {
                                    withAnimation(.spring(duration: 0.35)) {
                                        proxy.scrollTo(target.id, anchor: .top)
                                    }
                                }
                            }
                            weekSessions(matches)
                        } else {
                            emptyState
                        }
                        weeklyLoadCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 48)
                }
            }
            .background(Color.axBackground)
            .navigationTitle("Training Plan")
#if os(iOS)
            .navigationBarTitleDisplayMode(.large)
#endif
            .scrollIndicators(.hidden)
            .sheet(isPresented: $showPlanSetup) {
                FrequencyOnboardingView().environment(store)
            }
            .sheet(item: $selectedMatch) { WorkoutDetailView(match: $0) }
            .onAppear {
                if let idx = store.weeklyPlans.firstIndex(where: { $0.isCurrentWeek }) {
                    selectedWeekIndex = idx
                }
            }
            .onChange(of: store.weeklyPlans) { _, _ in
                if let idx = store.weeklyPlans.firstIndex(where: { $0.isCurrentWeek }) {
                    selectedWeekIndex = idx
                }
            }
        }
    }

    private var currentWeek: WeeklyPlan? {
        guard !store.weeklyPlans.isEmpty, selectedWeekIndex < store.weeklyPlans.count else { return nil }
        return store.weeklyPlans[selectedWeekIndex]
    }

    // MARK: - Plan updated banner

    private var planUpdatedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .foregroundStyle(.axGreen)
            Text("Plan updated to match your new training frequency")
                .font(.caption.weight(.medium))
                .foregroundStyle(.axPrimary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.axGreen.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.axGreen.opacity(0.25), lineWidth: 1))
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(duration: 0.4), value: store.planWasRecentlyUpdated)
    }

    // MARK: - Week picker

    private var weekPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(store.weeklyPlans.enumerated()), id: \.0) { idx, week in
                    Button {
                        withAnimation(.spring(duration: 0.3)) { selectedWeekIndex = idx }
                    } label: {
                        Text(week.weekLabel)
                            .font(.system(size: 13, weight: selectedWeekIndex == idx ? .semibold : .regular))
                            .foregroundStyle(selectedWeekIndex == idx ? .axPrimary : .axSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(selectedWeekIndex == idx
                                        ? Color.axAccent.opacity(0.18)
                                        : Color.white.opacity(0.05))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(
                                selectedWeekIndex == idx ? Color.axAccent.opacity(0.5) : Color.clear,
                                lineWidth: 1))
                    }
                }
            }
        }
    }

    // MARK: - Week sessions (with live completion state)

    private var selectedWeekMatches: [SessionMatch] {
        guard let week = currentWeek else { return [] }
        return PlanMatchingEngine.matches(week: week, activities: store.weekActivities)
    }

    private func weekSessions(_ matches: [SessionMatch]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel((currentWeek?.isCurrentWeek ?? false) ? "THIS WEEK" : "PLANNED SESSIONS")
            if matches.isEmpty {
                Text("No training days this week.")
                    .font(.subheadline)
                    .foregroundStyle(.axTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 10) {
                    ForEach(matches) { m in
                        Button { selectedMatch = m } label: { SessionMatchCard(match: m) }
                            .buttonStyle(.plain)
                            .id(m.id)
                    }
                }
            }
        }
    }

    // MARK: - Weekly load card

    @ViewBuilder
    private var weeklyLoadCard: some View {
        // Driven by observed wellness load — only meaningful with real data.
        if let weeklyLoadChange = store.metrics?.weeklyLoadChange {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("WEEKLY LOAD PROGRESSION")

            let pct = Int(weeklyLoadChange * 100)
            let sign = pct >= 0 ? "+" : ""
            let isAggressive = pct > 15

            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isAggressive ? "exclamationmark.triangle" : "chart.bar.fill")
                    .font(.title3)
                    .foregroundStyle(isAggressive ? .axRed : .axGreen)
                    .frame(width: 42, height: 42)
                    .background((isAggressive ? Color.axRed : Color.axGreen).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Week-on-week change: \(sign)\(pct)%")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(isAggressive
                        ? "This is an aggressive week-on-week progression. Continuing this trend significantly increases injury risk. Consider holding load steady next week."
                        : "Your load progression is within safe limits. The 10% weekly increase guideline is a conservative but effective injury prevention heuristic."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.axSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        .background(Color.axSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.axBorder, lineWidth: 1))
        }
    }

    // MARK: - No plan yet

    private var noPlanState: some View {
        NoDataView(
            icon: "calendar.badge.plus",
            title: "No plan yet",
            message: "Tell us how you want to train each week and we'll build your plan. You can change it anytime.",
            actionTitle: "Create a plan"
        ) {
            showPlanSetup = true
        }
    }

    // MARK: - Empty state (plan present but selected week out of range)

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.axTertiary)
            Text("No plan generated yet")
                .font(.headline)
                .foregroundStyle(.axSecondary)
            Text("Set your training frequency in Settings to generate your first plan.")
                .font(.subheadline)
                .foregroundStyle(.axTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(40)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.axTertiary)
            .tracking(2)
    }
}

#Preview {
    NavigationStack {
        PlanView()
            .environment(AthleteStore())
    }
}
