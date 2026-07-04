import SwiftUI

/// Tap-the-ring detail sheet (§8): the full readiness explanation, contributing
/// conditions, and a trend graph per contributing metric — all the content that
/// used to crowd the main page.
struct ReadinessDetailView: View {
    let readiness: DailyReadiness
    @Environment(AthleteStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    scoreHeader
                    explanationSection
                    if !readiness.keyInsights.isEmpty { conditionsSection }
                    graphsSection
                }
                .padding(20)
            }
            .background(Color.axBackground)
            .navigationTitle("Readiness")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    // MARK: - Score header

    private var scoreHeader: some View {
        VStack(spacing: 14) {
            ReadinessRingView(score: readiness.score, status: readiness.status)
                .frame(width: 190, height: 190)
            AxPill(text: readiness.status.rawValue, color: readiness.status.color)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Explanation

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(readiness.displayVerdict)
                .font(.axDisplay(19, .heavy))
                .tracking(-0.3)
                .foregroundStyle(.axPrimary)
            Text(readiness.aiNarrative ?? readiness.explanation)
                .font(.axDisplay(13.5))
                .foregroundStyle(.axSecondary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "brain.head.profile")
                    .font(.subheadline).foregroundStyle(.axAccent).padding(.top, 1)
                Text(readiness.coachingNote)
                    .font(.axDisplay(13.5, .medium))
                    .foregroundStyle(.axAccent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.axAccent.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.axAccent.opacity(0.2), lineWidth: 1))
        }
    }

    // MARK: - Contributing conditions

    private var conditionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("CONTRIBUTING CONDITIONS")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(readiness.keyInsights) { MetricInsightCard(insight: $0) }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    // MARK: - Metric trend graphs

    private var graphsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("METRIC TRENDS")
            let graphs = metricGraphs
            if graphs.isEmpty && !hasFitnessData {
                Text("Connect a data source to see your HRV, resting HR, sleep, and load trends here.")
                    .font(.subheadline)
                    .foregroundStyle(.axTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
            } else {
                if hasFitnessData { fitnessFatigueCard }
                ForEach(graphs) { graphCard($0) }
            }
        }
    }

    // Fitness / Fatigue / Form (§12) — replaces the plain TSB line when present.
    private var hasFitnessData: Bool {
        guard let m = store.metrics else { return false }
        return Swift.min(m.ctlSeries.count, m.atlSeries.count) > 1
    }

    private var fitnessFatigueCard: some View {
        let m = store.metrics
        let n = Swift.min(m?.ctlSeries.count ?? 0, m?.atlSeries.count ?? 0, m?.trendDates.count ?? 0)
        return AxCard(radius: 18, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Fitness & Fatigue").font(.axDisplay(14, .bold)).foregroundStyle(.axPrimary)
                    Spacer()
                    Label("intervals.icu", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.axMono(9)).foregroundStyle(.axTertiary)
                }
                FitnessFatigueChart(
                    ctl: Array((m?.ctlSeries ?? []).suffix(n)),
                    atl: Array((m?.atlSeries ?? []).suffix(n)),
                    dates: Array((m?.trendDates ?? []).suffix(n))
                )
            }
        }
    }

    private func graphCard(_ g: GraphSpec) -> some View {
        AxCard(radius: 18, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(g.title)
                        .font(.axDisplay(14, .bold))
                        .foregroundStyle(.axPrimary)
                    Spacer()
                    if let source = g.source {
                        Label(source, systemImage: "antenna.radiowaves.left.and.right")
                            .font(.axMono(9))
                            .foregroundStyle(.axTertiary)
                    }
                }
                MetricChartView(values: g.values, dates: g.dates, color: g.color, format: g.format,
                                interactive: true)
                    .frame(height: 150)
            }
        }
    }

    // MARK: - Graph specs from the store's metrics

    private struct GraphSpec: Identifiable {
        let id: String
        let title: String
        let color: Color
        let values: [Double]
        let dates: [Date]
        let format: (Double) -> String
        let source: String?
    }

    private var metricGraphs: [GraphSpec] {
        guard let m = store.metrics else { return [] }
        let dates = m.trendDates
        func aligned(_ series: [Double]) -> ([Double], [Date]) {
            let n = Swift.min(series.count, dates.count)
            guard n > 1 else { return ([], []) }
            return (Array(series.suffix(n)), Array(dates.suffix(n)))
        }
        var out: [GraphSpec] = []
        let hrv = aligned(m.hrvSeries)
        if !hrv.0.isEmpty {
            out.append(GraphSpec(id: "hrv", title: "Heart Rate Variability", color: .axGreen,
                                 values: hrv.0, dates: hrv.1,
                                 format: { "\(Int($0.rounded())) ms" },
                                 source: m.source(for: .hrv)?.displayName))
        }
        let rhr = aligned(m.restingHRSeries)
        if !rhr.0.isEmpty {
            out.append(GraphSpec(id: "rhr", title: "Resting Heart Rate", color: .axRed,
                                 values: rhr.0, dates: rhr.1,
                                 format: { "\(Int($0.rounded())) bpm" },
                                 source: m.source(for: .restingHR)?.displayName))
        }
        // Days with no sleep reading are stored as 0 h; drop them so the line
        // tracks real nights instead of dipping to the floor.
        let sleep = aligned(m.sleepSeries)
        let sleepNights = Array(zip(sleep.0, sleep.1).filter { $0.0 > 0 })
        if sleepNights.count > 1 {
            out.append(GraphSpec(id: "sleep", title: "Sleep", color: .axPurple,
                                 values: sleepNights.map(\.0), dates: sleepNights.map(\.1),
                                 format: { String(format: "%.1f h", $0) },
                                 source: m.source(for: .sleep)?.displayName))
        }
        let vo2 = aligned(m.vo2maxSeries)
        if !vo2.0.isEmpty {
            out.append(GraphSpec(id: "vo2max", title: "VO₂max", color: .axBlue,
                                 values: vo2.0, dates: vo2.1,
                                 format: { String(format: "%.1f", $0) },
                                 source: "intervals.icu"))
        }
        return out
    }

}
