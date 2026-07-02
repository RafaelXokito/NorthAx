import SwiftUI

struct MetricInsightCard: View {
    let insight: MetricInsight

    var trendColor: Color {
        switch insight.trend {
        case .up:      return .axGreen
        case .down:    return .axAmber
        case .warning: return .axRed
        case .neutral: return .axSecondary
        }
    }

    var body: some View {
        AxCard(radius: 18, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                // Header row
                HStack(alignment: .center) {
                    Text(insight.label.uppercased())
                        .font(.axMono(10, .semibold))
                        .foregroundStyle(.axTertiary)
                        .tracking(1.5)
                    Spacer()
                    Image(systemName: insight.trend.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(trendColor)
                }

                // Value
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(insight.value)
                        .font(.axDisplay(30, .heavy))
                        .tracking(-0.6)
                        .foregroundStyle(.axPrimary)
                    Text(insight.unit.uppercased())
                        .font(.axMono(11))
                        .foregroundStyle(.axSecondary)
                        .padding(.bottom, 2)
                }

                // Status label
                Text(insight.explanation)
                    .font(.axDisplay(12, .semibold))
                    .foregroundStyle(trendColor)

                Rectangle()
                    .fill(Color.axBorder)
                    .frame(height: 1)

                // Context
                Text(insight.context)
                    .font(.axDisplay(11))
                    .foregroundStyle(.axTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .frame(width: 136, alignment: .leading)
        }
    }
}
