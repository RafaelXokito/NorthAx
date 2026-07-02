import SwiftUI

struct PlanView: View {
    @Environment(AthleteStore.self) private var store
    @State private var weekOffset = 0
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
                        if let data = store.weekData(offset: weekOffset) {
                            WeekGlanceView(week: data.week, matches: data.matches,
                                           offset: $weekOffset, maxForward: store.maxFutureWeekOffset) { date in
                                if let target = data.matches.first(where: { $0.day.date == date }) {
                                    withAnimation(.spring(duration: 0.35)) {
                                        proxy.scrollTo(target.id, anchor: .top)
                                    }
                                }
                            }
                            weekSessions(data)
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
        }
    }

    // MARK: - Plan updated banner

    private var planUpdatedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .foregroundStyle(.axGreen)
            Text("Plan updated to match your new training frequency")
                .font(.axDisplay(12, .medium))
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

    // MARK: - Week sessions (with live completion state)

    private func weekSessions(_ data: WeekData) -> some View {
        let label = data.isHistorical ? "COMPLETED WORKOUTS"
            : (data.offset == 0 ? "THIS WEEK" : "PLANNED SESSIONS")
        return VStack(alignment: .leading, spacing: 12) {
            SectionLabel(label)
            if data.matches.isEmpty {
                Text(data.isHistorical ? "No workouts imported for this week." : "No training days this week.")
                    .font(.axDisplay(13.5))
                    .foregroundStyle(.axTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 10) {
                    ForEach(data.matches) { m in
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
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("WEEKLY LOAD PROGRESSION")

                let pct = Int(weeklyLoadChange * 100)
                let sign = pct >= 0 ? "+" : ""
                let isAggressive = pct > 15

                AxCard(radius: 20, padding: 20) {
                    HStack(alignment: .top, spacing: 14) {
                        IconTile(systemName: isAggressive ? "exclamationmark.triangle" : "chart.bar.fill",
                                 color: isAggressive ? .axRed : .axGreen,
                                 size: 42, radius: 10)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Week-on-week change: \(sign)\(pct)%")
                                .font(.axDisplay(15, .bold))
                                .foregroundStyle(.axPrimary)

                            Text(isAggressive
                                ? "This is an aggressive week-on-week progression. Continuing this trend significantly increases injury risk. Consider holding load steady next week."
                                : "Your load progression is within safe limits. The 10% weekly increase guideline is a conservative but effective injury prevention heuristic."
                            )
                            .font(.axDisplay(13))
                            .foregroundStyle(.axSecondary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
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
                .font(.axDisplay(16, .bold))
                .foregroundStyle(.axSecondary)
            Text("Set your training frequency in Settings to generate your first plan.")
                .font(.axDisplay(13.5))
                .foregroundStyle(.axTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(40)
    }
}

#Preview {
    NavigationStack {
        PlanView()
            .environment(AthleteStore())
    }
}
