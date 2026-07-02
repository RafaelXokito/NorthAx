import SwiftUI

/// Compact session card with live completion state and, once matched to an
/// imported workout, its actual stats. Shared by the plan week list (§7). The
/// caller wraps it in a Button to open the detail view.
struct SessionMatchCard: View {
    let match: SessionMatch

    var body: some View {
        let session = match.session
        let past = match.completion == .missed || match.completion.isCompleted
        return AxCard(radius: 16, padding: 16, highlighted: match.day.isToday) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    IconTile(systemName: session.domain.icon,
                             color: past ? .axTertiary : session.domain.color,
                             size: 44)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.title)
                            .font(.axDisplay(15, .bold))
                            .foregroundStyle(.axPrimary)
                        Text("\(dayLabel) · \(session.duration) MIN · \(session.intensityLabel)".uppercased())
                            .font(.axMono(10))
                            .tracking(0.6)
                            .foregroundStyle(.axSecondary)
                    }
                    Spacer()
                    CompletionPill(completion: match.completion)
                }

                if let a = match.activity {
                    Rectangle().fill(Color.axBorder).frame(height: 1)
                    HStack(spacing: 16) {
                        stat("Time", a.formattedDuration)
                        if let dist = a.formattedDistance { stat("Dist", dist) }
                        if let hr = a.avgHeartRate { stat("Avg HR", "\(hr)") }
                        if let load = a.trainingLoad { stat("Load", String(format: "%.0f", load)) }
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.axMono(9, .semibold)).foregroundStyle(.axTertiary).tracking(0.8)
            Text(value).font(.axDisplay(13, .bold)).foregroundStyle(.axPrimary)
        }
    }

    private var dayLabel: String {
        if match.day.isToday { return "Today" }
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        if Calendar.current.isDate(match.day.date, inSameDayAs: tomorrow) { return "Tomorrow" }
        return match.day.weekdayShort
    }
}
