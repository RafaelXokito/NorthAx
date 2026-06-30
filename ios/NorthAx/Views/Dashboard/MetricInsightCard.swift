import SwiftUI

struct MetricInsightCard: View {
    let insight: MetricInsight

    var trendColor: Color {
        switch insight.trend {
        case .up:      return .axGreen
        case .down:    return Color(red: 1.0, green: 0.65, blue: 0.2)
        case .warning: return .axRed
        case .neutral: return .axSecondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row
            HStack(alignment: .center) {
                Text(insight.label.uppercased())
                    .font(.system(size: 10, weight: .semibold))
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
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(insight.unit)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.axSecondary)
                    .padding(.bottom, 2)
            }

            // Status label
            Text(insight.explanation)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(trendColor)

            Rectangle()
                .fill(Color.axBorder)
                .frame(height: 1)

            // Context
            Text(insight.context)
                .font(.system(size: 11))
                .foregroundStyle(.axTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .padding(16)
        .frame(width: 168, alignment: .leading)
        .background(Color.axSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.axBorder, lineWidth: 1)
        )
    }
}
