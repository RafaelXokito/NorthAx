import SwiftUI

struct MetricsView: View {
    @Environment(AthleteStore.self) private var store

    var body: some View {
        ScrollView {
            if let metrics = store.metrics, let readiness = store.readiness {
                VStack(spacing: 20) {
                    metricSection(
                        title: "Heart Rate Variability",
                        icon: "waveform.path.ecg",
                        iconColor: .axGreen,
                        value: "\(Int(metrics.hrv)) ms",
                        statusLabel: readiness.hrvScore >= 80 ? "Strong recovery" : (readiness.hrvScore >= 60 ? "Normal" : "Suppressed"),
                        statusColor: scoreColor(readiness.hrvScore),
                        detail: "Your HRV reflects the balance of your autonomic nervous system. A higher reading — relative to your personal baseline — indicates your body has recovered from recent training stress.",
                        rows: [
                            ("Today", "\(Int(metrics.hrv)) ms"),
                            ("7-Day Baseline", "\(Int(metrics.hrvBaseline)) ms"),
                            ("Change", changeString(metrics.hrvChange * 100, unit: "%")),
                            ("Score", "\(readiness.hrvScore)/100")
                        ],
                        trend: metrics.hrvTrend
                    )

                    metricSection(
                        title: "Sleep",
                        icon: "moon.stars",
                        iconColor: .axPurple,
                        value: String(format: "%.1f hrs", metrics.sleepDuration),
                        statusLabel: metrics.sleepScore >= 80 ? "Well rested" : (metrics.sleepScore >= 60 ? "Adequate" : "Insufficient"),
                        statusColor: scoreColor(metrics.sleepScore),
                        detail: "Sleep is when your body synthesises the adaptations from training — releasing growth hormone, repairing tissue, and consolidating motor patterns. No supplement replaces it.",
                        rows: [
                            ("Duration", String(format: "%.1f hrs", metrics.sleepDuration)),
                            ("Sleep Score", "\(metrics.sleepScore)/100"),
                            ("Deep Sleep", String(format: "%.1f hrs", metrics.deepSleep)),
                            ("REM Sleep", String(format: "%.1f hrs", metrics.remSleep)),
                            ("Sleep Debt", String(format: "%.1f hrs", metrics.sleepDebt))
                        ],
                        trend: nil
                    )

                    metricSection(
                        title: "Training Load",
                        icon: "chart.line.uptrend.xyaxis",
                        iconColor: .axAccent,
                        value: "TSB \(metrics.trainingBalance >= 0 ? "+" : "")\(Int(metrics.trainingBalance))",
                        statusLabel: abs(metrics.trainingBalance) < 10 ? "Balanced" : (metrics.trainingBalance < 0 ? "Fatigued" : "Fresh"),
                        statusColor: abs(metrics.trainingBalance) < 10 ? .axGreen : (metrics.trainingBalance < -15 ? .axRed : Color(red: 1.0, green: 0.7, blue: 0.2)),
                        detail: "Training Stress Balance (TSB) = Fitness (CTL) minus Fatigue (ATL). Peak performance happens in a narrow window around zero — enough fitness without excess fatigue.",
                        rows: [
                            ("Fitness (CTL)", String(format: "%.0f", metrics.chronicLoad)),
                            ("Fatigue (ATL)", String(format: "%.0f", metrics.acuteLoad)),
                            ("Balance (TSB)", "\(metrics.trainingBalance >= 0 ? "+" : "")\(Int(metrics.trainingBalance))"),
                            ("Weekly Change", changeString(metrics.weeklyLoadChange * 100, unit: "%")),
                            ("Load Score", "\(readiness.loadScore)/100")
                        ],
                        trend: nil
                    )

                    metricSection(
                        title: "Cardiovascular",
                        icon: "heart.fill",
                        iconColor: .axRed,
                        value: "\(metrics.restingHR) bpm",
                        statusLabel: metrics.restingHRChange <= 0 ? "Efficient" : (metrics.restingHRChange > 5 ? "Elevated" : "Slightly elevated"),
                        statusColor: metrics.restingHRChange <= 0 ? .axGreen : (metrics.restingHRChange > 5 ? .axRed : Color(red: 1.0, green: 0.7, blue: 0.2)),
                        detail: "Resting heart rate is a reliable secondary indicator of recovery. When your body is stressed, your heart works harder at rest. A reading at or below your personal baseline confirms the HRV signal.",
                        rows: [
                            ("Resting HR", "\(metrics.restingHR) bpm"),
                            ("Baseline", "\(metrics.restingHRBaseline) bpm"),
                            ("Change", changeString(Double(metrics.restingHRChange), unit: " bpm"))
                        ],
                        trend: nil
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 48)
            } else {
                NoDataView(
                    icon: "chart.xyaxis.line",
                    title: "No metrics yet",
                    message: "Connect a data source to see your HRV, sleep, training load, and cardiovascular trends here.",
                    actionTitle: "Enable integrations"
                ) {
                    store.selectedTab = .settings
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
        }
        .background(Color.axBackground)
        .navigationTitle("Metrics")
#if os(iOS)
        .navigationBarTitleDisplayMode(.large)
#endif
        .scrollIndicators(.hidden)
    }

    // MARK: - Metric section card

    private func metricSection(
        title: String,
        icon: String,
        iconColor: Color,
        value: String,
        statusLabel: String,
        statusColor: Color,
        detail: String,
        rows: [(String, String)],
        trend: [Double]?
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(iconColor)
                    .frame(width: 42, height: 42)
                    .background(iconColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(statusLabel)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                        .fontWeight(.semibold)
                }

                Spacer()

                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            // Trend sparkline
            if let trend = trend, trend.count > 1 {
                SparklineView(values: trend, color: iconColor)
                    .frame(height: 36)
            }

            Rectangle()
                .fill(Color.axBorder)
                .frame(height: 1)

            // Detail explanation
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.axSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(Color.axBorder)
                .frame(height: 1)

            // Data rows
            VStack(spacing: 10) {
                ForEach(rows, id: \.0) { row in
                    HStack {
                        Text(row.0)
                            .font(.subheadline)
                            .foregroundStyle(.axSecondary)
                        Spacer()
                        Text(row.1)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.axSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.axBorder, lineWidth: 1))
    }

    // MARK: - Helpers

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...100: return .axGreen
        case 60..<80:  return Color(red: 1.0, green: 0.7, blue: 0.2)
        default:       return .axRed
        }
    }

    private func changeString(_ value: Double, unit: String) -> String {
        let sign = value >= 0 ? "+" : ""
        if unit == "%" {
            return "\(sign)\(String(format: "%.0f", value))\(unit)"
        }
        return "\(sign)\(String(format: "%.0f", value))\(unit)"
    }
}

// MARK: - Sparkline

struct SparklineView: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let minVal = values.min() ?? 0
            let maxVal = values.max() ?? 1
            let range = Swift.max(maxVal - minVal, 1)
            let w = geo.size.width
            let h = geo.size.height
            let step = w / Double(values.count - 1)

            let points = values.enumerated().map { i, v in
                CGPoint(x: Double(i) * step, y: h - ((v - minVal) / range) * h)
            }

            ZStack {
                // Fill
                Path { p in
                    p.move(to: CGPoint(x: points[0].x, y: h))
                    points.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: points.last!.x, y: h))
                    p.closeSubpath()
                }
                .fill(color.opacity(0.15))

                // Line
                Path { p in
                    guard let first = points.first else { return }
                    p.move(to: first)
                    points.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                // Last point dot
                if let last = points.last {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                        .position(last)
                }
            }
        }
    }
}
