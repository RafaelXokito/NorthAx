import SwiftUI

/// Compact session card with live completion state and, once matched to an
/// imported workout, its actual stats. Shared by the plan week list (§7). The
/// caller wraps it in a Button to open the detail view.
struct SessionMatchCard: View {
    let match: SessionMatch

    var body: some View {
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
                    Text("\(dayLabel) · \(session.duration) min · \(session.intensityLabel)")
                        .font(.caption)
                        .foregroundStyle(.axSecondary)
                }
                Spacer()
                completionBadge
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
        .padding(16)
        .background(match.day.isToday ? Color.axAccent.opacity(0.06) : Color.axSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(
            match.day.isToday ? Color.axAccent.opacity(0.3) : Color.axBorder, lineWidth: 1))
    }

    private var completionBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: match.completion.icon).font(.system(size: 10, weight: .semibold))
            Text(match.completion.label).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(match.completion.color)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(match.completion.color.opacity(0.12))
        .clipShape(Capsule())
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(.axTertiary).tracking(0.5)
            Text(value).font(.system(size: 13, weight: .semibold)).foregroundStyle(.axPrimary)
        }
    }

    private var dayLabel: String {
        if match.day.isToday { return "Today" }
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        if Calendar.current.isDate(match.day.date, inSameDayAs: tomorrow) { return "Tomorrow" }
        return match.day.weekdayShort
    }
}
