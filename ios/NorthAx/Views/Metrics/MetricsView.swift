import SwiftUI

struct MetricsView: View {
    @Environment(AthleteStore.self) private var store
    @State private var selected: MetricDetail?

    var body: some View {
        ScrollView {
            if let metrics = store.metrics, let readiness = store.readiness {
                VStack(spacing: 20) {
                    ForEach(details(metrics: metrics, readiness: readiness)) { detail in
                        card(detail)
                    }
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
        .sheet(item: $selected) { MetricDetailView(detail: $0) }
    }

    // MARK: - Card (header + graph; tap opens the detail modal)

    private func card(_ detail: MetricDetail) -> some View {
        Button { selected = detail } label: {
            VStack(alignment: .leading, spacing: 14) {
                MetricHeader(detail: detail)
                MetricChartView(
                    values: Array(detail.series.suffix(30)),
                    dates: Array(detail.dates.suffix(30)),
                    color: detail.color,
                    format: detail.format
                )
                .frame(height: 150)
            }
            .padding(20)
            .background(Color.axSurface)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.axBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Metric definitions

    private func details(metrics: TrainingMetrics, readiness: DailyReadiness) -> [MetricDetail] {
        let dates = metrics.trendDates
        return [
            MetricDetail(
                id: "Heart Rate Variability",
                title: "Heart Rate Variability",
                icon: "waveform.path.ecg",
                color: .axGreen,
                value: "\(Int(metrics.hrv)) ms",
                statusLabel: readiness.hrvScore >= 80 ? "Strong recovery" : (readiness.hrvScore >= 60 ? "Normal" : "Suppressed"),
                statusColor: scoreColor(readiness.hrvScore),
                description: "Your HRV reflects the balance of your autonomic nervous system. A higher reading — relative to your personal baseline — indicates your body has recovered from recent training stress.",
                rows: [
                    ("Today", "\(Int(metrics.hrv)) ms"),
                    ("7-Day Baseline", "\(Int(metrics.hrvBaseline)) ms"),
                    ("Change", changeString(metrics.hrvChange * 100, unit: "%")),
                    ("Score", "\(readiness.hrvScore)/100")
                ],
                series: metrics.hrvSeries,
                dates: dates,
                format: { "\(Int($0.rounded())) ms" }
            ),
            MetricDetail(
                id: "Sleep",
                title: "Sleep",
                icon: "moon.stars",
                color: .axPurple,
                value: String(format: "%.1f hrs", metrics.sleepDuration),
                statusLabel: metrics.sleepScore >= 80 ? "Well rested" : (metrics.sleepScore >= 60 ? "Adequate" : "Insufficient"),
                statusColor: scoreColor(metrics.sleepScore),
                description: "Sleep is when your body synthesises the adaptations from training — releasing growth hormone, repairing tissue, and consolidating motor patterns. No supplement replaces it.",
                rows: [
                    ("Duration", String(format: "%.1f hrs", metrics.sleepDuration)),
                    ("Sleep Score", "\(metrics.sleepScore)/100"),
                    ("Deep Sleep", String(format: "%.1f hrs", metrics.deepSleep)),
                    ("REM Sleep", String(format: "%.1f hrs", metrics.remSleep)),
                    ("Sleep Debt", String(format: "%.1f hrs", metrics.sleepDebt))
                ],
                series: metrics.sleepSeries,
                dates: dates,
                format: { String(format: "%.1f h", $0) }
            ),
            MetricDetail(
                id: "Training Load",
                title: "Training Load",
                icon: "chart.line.uptrend.xyaxis",
                color: .axAccent,
                value: "TSB \(metrics.trainingBalance >= 0 ? "+" : "")\(Int(metrics.trainingBalance))",
                statusLabel: abs(metrics.trainingBalance) < 10 ? "Balanced" : (metrics.trainingBalance < 0 ? "Fatigued" : "Fresh"),
                statusColor: abs(metrics.trainingBalance) < 10 ? .axGreen : (metrics.trainingBalance < -15 ? .axRed : Color(red: 1.0, green: 0.7, blue: 0.2)),
                description: "Training Stress Balance (TSB) = Fitness (CTL) minus Fatigue (ATL). Peak performance happens in a narrow window around zero — enough fitness without excess fatigue.",
                rows: [
                    ("Fitness (CTL)", String(format: "%.0f", metrics.chronicLoad)),
                    ("Fatigue (ATL)", String(format: "%.0f", metrics.acuteLoad)),
                    ("Balance (TSB)", "\(metrics.trainingBalance >= 0 ? "+" : "")\(Int(metrics.trainingBalance))"),
                    ("Weekly Change", changeString(metrics.weeklyLoadChange * 100, unit: "%")),
                    ("Load Score", "\(readiness.loadScore)/100")
                ],
                series: metrics.tsbSeries,
                dates: dates,
                format: { "\($0 >= 0 ? "+" : "")\(Int($0.rounded()))" }
            ),
            MetricDetail(
                id: "Cardiovascular",
                title: "Cardiovascular",
                icon: "heart.fill",
                color: .axRed,
                value: "\(metrics.restingHR) bpm",
                statusLabel: metrics.restingHRChange <= 0 ? "Efficient" : (metrics.restingHRChange > 5 ? "Elevated" : "Slightly elevated"),
                statusColor: metrics.restingHRChange <= 0 ? .axGreen : (metrics.restingHRChange > 5 ? .axRed : Color(red: 1.0, green: 0.7, blue: 0.2)),
                description: "Resting heart rate is a reliable secondary indicator of recovery. When your body is stressed, your heart works harder at rest. A reading at or below your personal baseline confirms the HRV signal.",
                rows: [
                    ("Resting HR", "\(metrics.restingHR) bpm"),
                    ("Baseline", "\(metrics.restingHRBaseline) bpm"),
                    ("Change", changeString(Double(metrics.restingHRChange), unit: " bpm"))
                ],
                series: metrics.restingHRSeries,
                dates: dates,
                format: { "\(Int($0.rounded())) bpm" }
            )
        ]
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
