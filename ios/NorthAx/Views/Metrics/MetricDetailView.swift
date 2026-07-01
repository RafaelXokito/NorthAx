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
            Image(systemName: detail.icon)
                .font(.title3)
                .foregroundStyle(detail.color)
                .frame(width: 42, height: 42)
                .background(detail.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(detail.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(detail.statusLabel)
                    .font(.caption)
                    .foregroundStyle(detail.statusColor)
                    .fontWeight(.semibold)
            }

            Spacer()

            Text(detail.value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
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
                            .font(.caption)
                            .foregroundStyle(.axTertiary)
                    }

                    if detail.series.count > 1 {
                        Picker("Range", selection: $range) {
                            ForEach(ChartRange.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        MetricChartView(
                            values: sliced(detail.series),
                            dates: sliced(detail.dates),
                            color: detail.color,
                            format: detail.format,
                            interactive: true
                        )
                        .frame(height: 240)

                        Text("Touch and drag the graph to read any day.")
                            .font(.caption)
                            .foregroundStyle(.axTertiary)
                    }

                    divider
                    Text(detail.description)
                        .font(.subheadline)
                        .foregroundStyle(.axSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    divider
                    VStack(spacing: 10) {
                        ForEach(detail.rows, id: \.0) { row in
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
