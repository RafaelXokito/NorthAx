import SwiftUI

struct PlanView: View {
    @Environment(AthleteStore.self) private var store
    @State private var selectedWeekIndex: Int = 0
    @State private var showPlanSetup = false

    var body: some View {
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
                        weekDotRow(week)
                        upcomingSessions(week)
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
            FrequencyOnboardingView()
                .environment(store)
        }
        .onAppear {
            // Jump to current week on appear
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

    // MARK: - Week dot row

    private func weekDotRow(_ week: WeeklyPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("WEEK AT A GLANCE")

            HStack(spacing: 0) {
                ForEach(week.days) { day in
                    VStack(spacing: 6) {
                        Text(day.weekdayShort)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(day.isToday ? .axAccent : .axTertiary)
                            .tracking(0.5)

                        ZStack {
                            Circle()
                                .fill(dotFill(day))
                                .frame(width: 36, height: 36)

                            if day.isToday {
                                Circle()
                                    .stroke(Color.axAccent, lineWidth: 1.5)
                                    .frame(width: 36, height: 36)
                            }

                            Image(systemName: dotIcon(day))
                                .font(.system(size: 13))
                                .foregroundStyle(dotIconColor(day))
                        }

                        Text(day.dayNumber)
                            .font(.system(size: 9))
                            .foregroundStyle(day.isToday ? .axAccent : .axTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(16)
            .background(Color.axSurface)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.axBorder, lineWidth: 1))
        }
    }

    private func dotFill(_ day: PlannedDay) -> Color {
        if day.isPast && !day.isToday { return Color.white.opacity(0.06) }
        if day.isRest { return Color.white.opacity(0.04) }
        if let domain = day.sessions.first?.domain { return domain.color.opacity(day.isToday ? 0.22 : 0.14) }
        return Color.white.opacity(0.04)
    }

    private func dotIcon(_ day: PlannedDay) -> String {
        if day.isRest { return "moon" }
        return day.sessions.count > 1 ? "square.stack.fill" : (day.sessions.first?.domain.icon ?? "moon")
    }

    private func dotIconColor(_ day: PlannedDay) -> Color {
        if day.isPast && !day.isToday { return .axTertiary }
        if day.isToday { return .axAccent }
        if day.isRest { return .axTertiary }
        return day.sessions.first?.domain.color ?? .axTertiary
    }

    // MARK: - Upcoming sessions list

    private func upcomingSessions(_ week: WeeklyPlan) -> some View {
        let trainingDays = week.days.filter { !$0.isRest && !$0.sessions.isEmpty }

        return VStack(alignment: .leading, spacing: 14) {
            sectionLabel(week.isCurrentWeek ? "UPCOMING SESSIONS" : "PLANNED SESSIONS")

            if trainingDays.isEmpty {
                Text("No training days this week.")
                    .font(.subheadline)
                    .foregroundStyle(.axTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 10) {
                    ForEach(trainingDays) { day in
                        ForEach(day.sessions) { session in
                            CollapsibleSessionRow(day: day, session: session)
                        }
                    }
                }
            }
        }
    }

    // Session rows are rendered by CollapsibleSessionRow (defined below).

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

// MARK: - Collapsible upcoming-session row

/// A plan session that shows only a summary until tapped; the workout lines and
/// the breakdown (effort graph / exercise list) appear only when expanded.
private struct CollapsibleSessionRow: View {
    @Environment(AthleteStore.self) private var store
    let day: PlannedDay
    let session: PlannedSession
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(duration: 0.3)) { expanded.toggle() }
            } label: { header }
            .buttonStyle(.plain)

            if expanded {
                if !session.workoutLines.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(session.workoutLines.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.caption2).foregroundStyle(.axTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                SessionBreakdownView(domain: session.domain, workout: session.workout,
                                     exercises: session.exercises)
            }
        }
        .padding(16)
        .background(day.isToday ? Color.axAccent.opacity(0.07) : Color.axSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(
            day.isToday ? Color.axAccent.opacity(0.3) : Color.axBorder, lineWidth: 1))
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: session.domain.icon)
                .font(.title3)
                .foregroundStyle(day.isPast ? .axTertiary : session.domain.color)
                .frame(width: 44, height: 44)
                .background((day.isPast ? Color.white : session.domain.color).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(day.isPast ? .axSecondary : .white)
                    .strikethrough(day.isPast, color: .axTertiary)
                Text(session.subtitle).font(.caption).foregroundStyle(.axSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(dayLabel).font(.caption.weight(.semibold))
                    .foregroundStyle(day.isToday ? .axAccent : .axSecondary)
                Text("\(session.duration) min").font(.caption).foregroundStyle(.axTertiary)
            }

            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.caption.bold()).foregroundStyle(.axTertiary)
        }
    }

    private var dayLabel: String {
        if day.isToday { return "Today" }
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        if Calendar.current.isDate(day.date, inSameDayAs: tomorrow) { return "Tomorrow" }
        return day.weekdayShort
    }
}

#Preview {
    NavigationStack {
        PlanView()
            .environment(AthleteStore())
    }
}
