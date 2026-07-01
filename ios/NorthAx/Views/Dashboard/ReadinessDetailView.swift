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
        VStack(spacing: 12) {
            ReadinessRingView(score: readiness.score, status: readiness.status)
                .frame(width: 170, height: 170)
            Text(readiness.status.rawValue)
                .font(.title2.bold())
                .foregroundStyle(readiness.status.ringColor)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Explanation

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(readiness.displayVerdict)
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text(readiness.aiNarrative ?? readiness.explanation)
                .font(.subheadline)
                .foregroundStyle(.axSecondary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "brain.head.profile")
                    .font(.subheadline).foregroundStyle(.axAccent).padding(.top, 1)
                Text(readiness.coachingNote)
                    .font(.subheadline.italic())
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
            sectionLabel("CONTRIBUTING CONDITIONS")
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
            sectionLabel("METRIC TRENDS")
            let graphs = metricGraphs
            if graphs.isEmpty {
                Text("Connect a data source to see your HRV, resting HR, sleep, and load trends here.")
                    .font(.subheadline)
                    .foregroundStyle(.axTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
            } else {
                ForEach(graphs) { graphCard($0) }
            }
        }
    }

    private func graphCard(_ g: GraphSpec) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(g.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                if let source = g.source {
                    Label(source, systemImage: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.axTertiary)
                }
            }
            MetricChartView(values: g.values, dates: g.dates, color: g.color, format: g.format)
                .frame(height: 150)
        }
        .padding(16)
        .background(Color.axSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.axBorder, lineWidth: 1))
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
        let sleep = aligned(m.sleepSeries)
        if !sleep.0.isEmpty {
            out.append(GraphSpec(id: "sleep", title: "Sleep", color: .axPurple,
                                 values: sleep.0, dates: sleep.1,
                                 format: { String(format: "%.1f h", $0) },
                                 source: m.source(for: .sleep)?.displayName))
        }
        let tsb = aligned(m.tsbSeries)
        if !tsb.0.isEmpty {
            out.append(GraphSpec(id: "tsb", title: "Training Balance (TSB)", color: .axAccent,
                                 values: tsb.0, dates: tsb.1,
                                 format: { "\($0 >= 0 ? "+" : "")\(Int($0.rounded()))" },
                                 source: "intervals.icu"))
        }
        return out
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.axTertiary)
            .tracking(2)
    }
}

extension DailyReadiness.Status {
    /// Ring / accent colour for this readiness status (shared by the ring + labels).
    var ringColor: Color {
        switch self {
        case .peak:     return .axAccent
        case .high:     return .axGreen
        case .moderate: return .axBlue
        case .low:      return Color(red: 1.0, green: 0.7, blue: 0.2)
        case .rest:     return .axRed
        }
    }
}
