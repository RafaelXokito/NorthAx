import SwiftUI

/// The 7-day strip with week navigation (§7 + §11). The header row (◀ label ▶)
/// and a swipe gesture browse past/future weeks; past is unlimited, future is
/// capped at `maxForward`. Each day shows its planned sport(s) / rest and a
/// completion state derived from matched workouts.
struct WeekGlanceView: View {
    let week: WeeklyPlan
    let matches: [SessionMatch]
    @Binding var offset: Int
    let maxForward: Int
    let onSelectDay: (Date) -> Void

    private var canForward: Bool { offset < maxForward }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            navHeader
            daysRow
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 24)
                        .onEnded { g in
                            if g.translation.width < -50 { step(1) }
                            else if g.translation.width > 50 { step(-1) }
                        }
                )
        }
    }

    // MARK: - Navigation header

    private var navHeader: some View {
        HStack {
            Button { step(-1) } label: {
                Image(systemName: "chevron.left").font(.subheadline.bold())
            }
            .foregroundStyle(.white)

            Spacer()

            VStack(spacing: 2) {
                Text(relativeLabel)
                    .font(.axMono(11, .semibold)).foregroundStyle(.axPrimary).tracking(1.2)
                Text(dateRange.uppercased())
                    .font(.axMono(9)).tracking(0.6).foregroundStyle(.axTertiary)
            }

            Spacer()

            Button { step(1) } label: {
                Image(systemName: "chevron.right").font(.subheadline.bold())
            }
            .foregroundStyle(canForward ? .white : .axTertiary.opacity(0.4))
            .disabled(!canForward)
        }
    }

    private func step(_ delta: Int) {
        let next = offset + delta
        guard next <= maxForward else { return }   // past is unlimited
        withAnimation(.spring(duration: 0.3)) { offset = next }
    }

    // MARK: - Days row

    private var daysRow: some View {
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

    private func dayColumn(_ day: PlannedDay) -> some View {
        let state = PlanMatchingEngine.dayState(day: day, matches: matches)
        return VStack(spacing: 7) {
            Text(day.weekdayShort.uppercased())
                .font(.axMono(9, .semibold))
                .foregroundStyle(day.isToday ? .axAccent : .axTertiary)
                .tracking(0.8)

            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(dotFill(day, state)).frame(width: 38, height: 38)
                if day.isToday {
                    RoundedRectangle(cornerRadius: 12).stroke(Color.axAccent, lineWidth: 1.5).frame(width: 38, height: 38)
                }
                Image(systemName: dotIcon(day, state))
                    .font(.system(size: 14))
                    .foregroundStyle(dotIconColor(day, state))
            }

            Image(systemName: state.icon)
                .font(.system(size: 9))
                .foregroundStyle(state == .rest ? .axTertiary : state.color)
                .opacity(state == .planned ? 0.35 : 1)
        }
    }

    private func dotFill(_ day: PlannedDay, _ state: SessionCompletion) -> Color {
        if state == .rest { return .axInset }
        if let domain = day.sessions.first?.domain {
            return domain.color.opacity(day.isToday ? 0.22 : 0.14)
        }
        return .axInset
    }

    private func dotIcon(_ day: PlannedDay, _ state: SessionCompletion) -> String {
        if state == .rest { return "moon" }
        return day.sessions.count > 1 ? "square.stack.fill" : (day.sessions.first?.domain.icon ?? "moon")
    }

    private func dotIconColor(_ day: PlannedDay, _ state: SessionCompletion) -> Color {
        if state == .rest { return .axTertiary }
        return day.sessions.first?.domain.color ?? .axTertiary
    }

    // MARK: - Labels

    private var relativeLabel: String {
        switch offset {
        case 0:  return "THIS WEEK"
        case -1: return "LAST WEEK"
        case 1:  return "NEXT WEEK"
        case ..<(-1): return "\(-offset) WEEKS AGO"
        default: return "IN \(offset) WEEKS"
        }
    }

    private var dateRange: String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        let end = Calendar.current.date(byAdding: .day, value: 6, to: week.weekStart) ?? week.weekStart
        return "\(f.string(from: week.weekStart)) – \(f.string(from: end))"
    }
}
