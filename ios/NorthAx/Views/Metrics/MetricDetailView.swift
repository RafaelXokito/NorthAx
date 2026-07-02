import SwiftUI

// One metric's full data, shared by the Metrics card and its detail modal.
struct MetricDetail: Identifiable {
    let id: String          // title — unique per metric
    let title: String
    let icon: String
    let color: Color
    let value: String       // headline value, e.g. "58 ms"
    let statusLabel: String
    let statusColor: Color
    let description: String
    let rows: [(String, String)]
    let series: [Double]    // full history, oldest→newest
    let dates: [Date]       // aligned with `series`
    let format: (Double) -> String   // value formatter for the graph axes/scrub
    let sourceLabel: String?         // which integration provided today's value

    init(id: String, title: String, icon: String, color: Color, value: String,
         statusLabel: String, statusColor: Color, description: String,
         rows: [(String, String)], series: [Double], dates: [Date],
         format: @escaping (Double) -> String, sourceLabel: String? = nil) {
        self.id = id; self.title = title; self.icon = icon; self.color = color
        self.value = value; self.statusLabel = statusLabel; self.statusColor = statusColor
        self.description = description; self.rows = rows; self.series = series
        self.dates = dates; self.format = format; self.sourceLabel = sourceLabel
    }
}

// Icon + title + status + value row, shared by card and modal (matches the
// app's existing metric header layout).
struct MetricHeader: View {
    let detail: MetricDetail

    var body: some View {
        HStack(spacing: 12) {
            IconTile(systemName: detail.icon, color: detail.color, size: 42, radius: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(detail.title)
                    .font(.axDisplay(15, .bold))
                    .foregroundStyle(.axPrimary)
                AxPill(text: detail.statusLabel, color: detail.statusColor)
            }

            Spacer()

            Text(detail.value)
                .font(.axDisplay(22, .heavy))
                .tracking(-0.44)
                .foregroundStyle(.axPrimary)
        }
    }
}

// Tap-to-open modal: range-switchable scrubbable graph, the metric description,
// and all related values (score, change %, baseline, …).
struct MetricDetailView: View {
    let detail: MetricDetail
    @Environment(\.dismiss) private var dismiss
    @State private var range: ChartRange = .d30

    enum ChartRange: Int, CaseIterable, Identifiable {
        case d7 = 7, d30 = 30, d90 = 90
        var id: Int { rawValue }
        var label: String { "\(rawValue)d" }
    }

    private func sliced<T>(_ arr: [T]) -> [T] { Array(arr.suffix(range.rawValue)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    MetricHeader(detail: detail)

                    if let source = detail.sourceLabel {
                        Label("Source: \(source)", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.axMono(10))
                            .foregroundStyle(.axTertiary)
                    }

                    if detail.series.count > 1 {
                        AxSegmented(
                            options: ChartRange.allCases.map { ($0, $0.label) },
                            selection: $range
                        )

                        MetricChartView(
                            values: sliced(detail.series),
                            dates: sliced(detail.dates),
                            color: detail.color,
                            format: detail.format,
                            interactive: true
                        )
                        .frame(height: 240)

                        Text("Touch and drag the graph to read any day.")
                            .font(.axDisplay(11.5))
                            .foregroundStyle(.axTertiary)
                    }

                    divider
                    Text(detail.description)
                        .font(.axDisplay(13.5))
                        .foregroundStyle(.axSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    divider
                    VStack(spacing: 10) {
                        ForEach(detail.rows, id: \.0) { row in
                            HStack {
                                Text(row.0)
                                    .font(.axDisplay(13.5))
                                    .foregroundStyle(.axSecondary)
                                Spacer()
                                Text(row.1)
                                    .font(.axMono(12, .semibold))
                                    .foregroundStyle(.axPrimary)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.axBackground)
            .navigationTitle(detail.title)
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.axBorder).frame(height: 1)
    }
}
