import SwiftUI

/// Latest AI verdict on progress toward one sport's goal (§ sport targets).
/// Shows a "Re-analyse plan" CTA when the athlete is off-trajectory.
struct GoalCheckCard: View {
    let check: GoalCheck
    let onReanalyse: () -> Void

    var body: some View {
        AxCard(radius: 16, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(check.domain.rawValue.uppercased())
                        .font(.axMono(10, .semibold))
                        .tracking(1.8)
                        .foregroundStyle(check.domain.color)
                    Spacer()
                    AxPill(text: pillText, color: pillColor)
                }

                Text(check.summary)
                    .font(.axDisplay(13.5))
                    .foregroundStyle(.axSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if check.verdict != .onTrack || check.recommendReplan {
                    Divider().overlay(Color.axBorder)
                    Button(action: onReanalyse) {
                        HStack(spacing: 6) {
                            Text("RE-ANALYSE PLAN")
                                .font(.axMono(10, .semibold))
                                .tracking(1.2)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(.axAccent)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var pillText: String {
        switch check.verdict {
        case .onTrack: "On track"
        case .behind: "Behind"
        case .ahead: "Ahead"
        }
    }

    private var pillColor: Color {
        switch check.verdict {
        case .onTrack: .axGreen
        case .behind: .axRed
        case .ahead: .axPurple
        }
    }
}
