import SwiftUI

struct MetricsView: View {
    @Environment(AthleteStore.self) private var store
    @State private var selected: MetricDetail?
    @State private var showManualEntry = false

    var body: some View {
        ScrollView {
            if let metrics = store.metrics, let readiness = store.readiness {
                VStack(spacing: 20) {
                    if metrics.ctlSeries.count > 1 && metrics.atlSeries.count > 1 {
                        fitnessFatigueCard(metrics)
                    }
                    ForEach(details(metrics: metrics, readiness: readiness) + vo2maxDetails(metrics)) { detail in
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showManualEntry = true } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("Log metrics manually")
            }
        }
        .sheet(item: $selected) { MetricDetailView(detail: $0) }
        .sheet(isPresented: $showManualEntry) { ManualEntryView() }
    }

    // MARK: - Card (header + range + graph + stat strip; tap opens the detail modal)

    private func card(_ detail: MetricDetail) -> some View {
        MetricCard(detail: detail) { selected = detail }
    }

    // MARK: - Fitness / Fatigue + VO₂max (§12)

    private func fitnessFatigueCard(_ metrics: TrainingMetrics) -> some View {
        let n = min(metrics.ctlSeries.count, metrics.atlSeries.count, metrics.trendDates.count)
        return AxCard(radius: 20, padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("FITNESS & FATIGUE")
                    .frame(maxWidth: .infinity, alignment: .leading)
                FitnessFatigueChart(
                    ctl: Array(metrics.ctlSeries.suffix(n)),
                    atl: Array(metrics.atlSeries.suffix(n)),
                    dates: Array(metrics.trendDates.suffix(n))
                )
            }
        }
    }

    private func vo2maxDetails(_ metrics: TrainingMetrics) -> [MetricDetail] {
        guard let vo2 = metrics.vo2max, metrics.vo2maxSeries.count > 1 else { return [] }
        return [MetricDetail(
            id: "VO₂max",
            title: "VO₂max",
            icon: "lungs.fill",
            color: .axBlue,
            value: String(format: "%.1f", vo2),
            statusLabel: "Aerobic capacity",
            statusColor: .axBlue,
            description: "VO₂max estimates the maximum oxygen your body can use during intense exercise — a strong indicator of aerobic fitness. It rises slowly with consistent training.",
            rows: [("Latest", String(format: "%.1f ml/kg/min", vo2))],
            series: metrics.vo2maxSeries,
            dates: metrics.trendDates,
            format: { String(format: "%.1f", $0) },
            sourceLabel: "intervals.icu"
        )]
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
                value: "\(Int(metrics.hrv))",
                unit: "ms",
                statusLabel: readiness.hrvScore >= 80 ? "Strong recovery" : (readiness.hrvScore >= 60 ? "Normal" : "Suppressed"),
                statusColor: scoreColor(readiness.hrvScore),
                delta: ("\(metrics.hrvChange >= 0 ? "▲" : "▼") \(changeString(metrics.hrvChange * 100, unit: "%")) / 7D",
                        metrics.hrvChange >= 0 ? .axGreen : .axAmber),
                description: "Your HRV reflects the balance of your autonomic nervous system. A higher reading — relative to your personal baseline — indicates your body has recovered from recent training stress.",
                rows: [
                    ("Today", "\(Int(metrics.hrv)) ms"),
                    ("7-Day Baseline", "\(Int(metrics.hrvBaseline)) ms"),
                    ("Change", changeString(metrics.hrvChange * 100, unit: "%")),
                    ("Score", "\(readiness.hrvScore)/100")
                ],
                strip: [
                    .init("Today", "\(Int(metrics.hrv))"),
                    .init("Base", "\(Int(metrics.hrvBaseline))"),
                    .init("Change", changeString(metrics.hrvChange * 100, unit: "%"),
                          color: metrics.hrvChange >= 0 ? .axGreen : .axAmber),
                    .init("Score", "\(readiness.hrvScore)")
                ],
                series: metrics.hrvSeries,
                dates: dates,
                format: { "\(Int($0.rounded())) ms" },
                sourceLabel: metrics.source(for: .hrv)?.displayName
            ),
            MetricDetail(
                id: "Sleep",
                title: "Sleep",
                icon: "moon.stars",
                color: .axPurple,
                value: String(format: "%.1f", metrics.sleepDuration),
                unit: "hrs",
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
                strip: [
                    .init("Today", String(format: "%.1f", metrics.sleepDuration)),
                    .init("Deep", String(format: "%.1f", metrics.deepSleep)),
                    .init("REM", String(format: "%.1f", metrics.remSleep)),
                    .init("Score", "\(metrics.sleepScore)")
                ],
                series: metrics.sleepSeries,
                dates: dates,
                format: { String(format: "%.1f h", $0) },
                sourceLabel: metrics.source(for: .sleep)?.displayName
            ),
            MetricDetail(
                id: "Training Load",
                title: "Training Load",
                icon: "chart.line.uptrend.xyaxis",
                color: .axAccent,
                value: "\(metrics.trainingBalance >= 0 ? "+" : "")\(Int(metrics.trainingBalance))",
                unit: "TSB",
                statusLabel: abs(metrics.trainingBalance) < 10 ? "Balanced" : (metrics.trainingBalance < 0 ? "Fatigued" : "Fresh"),
                statusColor: abs(metrics.trainingBalance) < 10 ? .axGreen : (metrics.trainingBalance < -15 ? .axRed : .axAmber),
                description: "Training Stress Balance (TSB) = Fitness (CTL) minus Fatigue (ATL). Peak performance happens in a narrow window around zero — enough fitness without excess fatigue.",
                rows: [
                    ("Fitness (CTL)", String(format: "%.0f", metrics.chronicLoad)),
                    ("Fatigue (ATL)", String(format: "%.0f", metrics.acuteLoad)),
                    ("Balance (TSB)", "\(metrics.trainingBalance >= 0 ? "+" : "")\(Int(metrics.trainingBalance))"),
                    ("Weekly Change", changeString(metrics.weeklyLoadChange * 100, unit: "%")),
                    ("Load Score", "\(readiness.loadScore)/100")
                ],
                strip: [
                    .init("Fitness", String(format: "%.0f", metrics.chronicLoad)),
                    .init("Fatigue", String(format: "%.0f", metrics.acuteLoad)),
                    .init("Week Δ", changeString(metrics.weeklyLoadChange * 100, unit: "%"),
                          color: metrics.weeklyLoadChange > 0.15 ? .axRed : .axGreen),
                    .init("Score", "\(readiness.loadScore)")
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
                value: "\(metrics.restingHR)",
                unit: "bpm",
                statusLabel: metrics.restingHRChange <= 0 ? "Efficient" : (metrics.restingHRChange > 5 ? "Elevated" : "Slightly elevated"),
                statusColor: metrics.restingHRChange <= 0 ? .axGreen : (metrics.restingHRChange > 5 ? .axRed : .axAmber),
                delta: ("\(metrics.restingHRChange > 0 ? "▲" : "▼") \(changeString(Double(metrics.restingHRChange), unit: " BPM"))",
                        metrics.restingHRChange <= 0 ? .axGreen : .axAmber),
                description: "Resting heart rate is a reliable secondary indicator of recovery. When your body is stressed, your heart works harder at rest. A reading at or below your personal baseline confirms the HRV signal.",
                rows: [
                    ("Resting HR", "\(metrics.restingHR) bpm"),
                    ("Baseline", "\(metrics.restingHRBaseline) bpm"),
                    ("Change", changeString(Double(metrics.restingHRChange), unit: " bpm"))
                ],
                strip: [
                    .init("Today", "\(metrics.restingHR)"),
                    .init("Base", "\(metrics.restingHRBaseline)"),
                    .init("Change", changeString(Double(metrics.restingHRChange), unit: ""),
                          color: metrics.restingHRChange <= 0 ? .axGreen : .axAmber)
                ],
                series: metrics.restingHRSeries,
                dates: dates,
                format: { "\(Int($0.rounded())) bpm" },
                sourceLabel: metrics.source(for: .restingHR)?.displayName
            )
        ]
    }

    // MARK: - Helpers

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...100: return .axGreen
        case 60..<80:  return .axAmber
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

// One metric card: header, 7D/30D/90D range, chart, and an optional
// TODAY / BASE / CHANGE / SCORE strip under a hairline. Own struct so each
// card keeps its own selected range.
private struct MetricCard: View {
    let detail: MetricDetail
    let onTap: () -> Void

    @State private var range: MetricDetailView.ChartRange = .d30

    private func sliced<T>(_ arr: [T]) -> [T] { Array(arr.suffix(range.rawValue)) }

    var body: some View {
        AxCard(radius: 20, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                MetricHeader(detail: detail)

                if detail.series.count > MetricDetailView.ChartRange.d7.rawValue {
                    AxSegmented(
                        options: MetricDetailView.ChartRange.allCases.map { ($0, $0.label) },
                        selection: $range
                    )
                }

                MetricChartView(
                    values: sliced(detail.series),
                    dates: sliced(detail.dates),
                    color: detail.color,
                    format: detail.format
                )
                .frame(height: 150)

                if !detail.strip.isEmpty {
                    Rectangle().fill(Color.axBorder).frame(height: 1)
                    HStack(spacing: 0) {
                        ForEach(detail.strip) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.label)
                                    .font(.axMono(9, .semibold))
                                    .tracking(1.2)
                                    .textCase(.uppercase)
                                    .foregroundStyle(.axTertiary)
                                Text(item.value)
                                    .font(.axDisplay(15, .bold))
                                    .foregroundStyle(item.color)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
