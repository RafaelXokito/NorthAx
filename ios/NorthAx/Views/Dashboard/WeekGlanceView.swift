import SwiftUI

/// The 7-day strip at the top of the plan-centric dashboard (§7). Each day shows
/// its planned sport(s) (or a rest icon) and a completion state derived from
/// matched workouts. Today is highlighted; tapping a day scrolls to its card.
struct WeekGlanceView: View {
    let week: WeeklyPlan
    let matches: [SessionMatch]
    let onSelectDay: (Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("WEEK AT A GLANCE")
            HStack(spacing: 0) {
                ForEach(week.days) { day in
                    dayColumn(day)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelectDay(day.date) }
                }
            }
            .padding(16)
            .background(Color.axSurface)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.axBorder, lineWidth: 1))
        }
    }

    private func dayColumn(_ day: PlannedDay) -> some View {
        let state = PlanMatchingEngine.dayState(day: day, matches: matches)
        return VStack(spacing: 6) {
            Text(day.weekdayShort)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(day.isToday ? .axAccent : .axTertiary)
                .tracking(0.5)

            ZStack {
                Circle()
                    .fill(dotFill(day, state))
                    .frame(width: 36, height: 36)
                if day.isToday {
                    Circle().stroke(Color.axAccent, lineWidth: 1.5).frame(width: 36, height: 36)
                }
                Image(systemName: dotIcon(day, state))
                    .font(.system(size: 13))
                    .foregroundStyle(dotIconColor(day, state))
            }

            // Completion tick / state marker under the dot.
            Image(systemName: state.icon)
                .font(.system(size: 9))
                .foregroundStyle(state == .rest ? .axTertiary : state.color)
                .opacity(state == .planned ? 0.35 : 1)
        }
    }

    private func dotFill(_ day: PlannedDay, _ state: SessionCompletion) -> Color {
        if state == .rest { return Color.white.opacity(0.04) }
        if let domain = day.sessions.first?.domain {
            return domain.color.opacity(day.isToday ? 0.22 : 0.14)
        }
        return Color.white.opacity(0.04)
    }

    private func dotIcon(_ day: PlannedDay, _ state: SessionCompletion) -> String {
        if state == .rest { return "moon" }
        return day.sessions.count > 1 ? "square.stack.fill" : (day.sessions.first?.domain.icon ?? "moon")
    }

    private func dotIconColor(_ day: PlannedDay, _ state: SessionCompletion) -> Color {
        if state == .rest { return .axTertiary }
        return day.sessions.first?.domain.color ?? .axTertiary
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.axTertiary)
            .tracking(2)
    }
}
