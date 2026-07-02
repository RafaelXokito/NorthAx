import SwiftUI

// One metric's full data, shared by the Metrics card and its detail modal.
struct MetricDetail: Identifiable {
    struct StripItem: Identifiable {
        let id: String   // label
        let value: String
        var color: Color = .axPrimary
        init(_ label: String, _ value: String, color: Color = .axPrimary) {
            self.id = label; self.value = value; self.color = color
        }
        var label: String { id }
    }

    let id: String          // title — unique per metric
    let title: String
    let icon: String
    let color: Color
    let value: String       // headline numeral, e.g. "116"
    let unit: String?       // small unit beside the numeral, e.g. "ms"
    let statusLabel: String
    let statusColor: Color
    let delta: (text: String, color: Color)?   // e.g. "▲ +1% / 7D"
    let description: String
    let rows: [(String, String)]
    let strip: [StripItem]  // TODAY / BASE / CHANGE / SCORE footer strip
    let series: [Double]    // full history, oldest→newest
    let dates: [Date]       // aligned with `series`
    let format: (Double) -> String   // value formatter for the graph axes/scrub
    let sourceLabel: String?         // which integration provided today's value

    init(id: String, title: String, icon: String, color: Color, value: String,
         unit: String? = nil, statusLabel: String, statusColor: Color,
         delta: (text: String, color: Color)? = nil, description: String,
         rows: [(String, String)], strip: [StripItem] = [],
         series: [Double], dates: [Date],
         format: @escaping (Double) -> String, sourceLabel: String? = nil) {
        self.id = id; self.title = title; self.icon = icon; self.color = color
        self.value = value; self.unit = unit
        self.statusLabel = statusLabel; self.statusColor = statusColor
        self.delta = delta; self.description = description; self.rows = rows
        self.strip = strip; self.series = series
        self.dates = dates; self.format = format; self.sourceLabel = sourceLabel
    }
}

// Icon + title + status + value row, shared by card and modal (matches the
// app's existing metric header layout).
struct MetricHeader: View {
    let detail: MetricDetail

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(systemName: detail.icon, color: detail.color, size: 46, radius: 12)

            VStack(alignment: .leading, spacing: 6) {
                Text(detail.title)
                    .font(.axDisplay(16, .bold))
                    .foregroundStyle(.axPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                AxPill(text: detail.statusLabel, color: detail.statusColor)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(detail.value)
                        .font(.axDisplay(30, .heavy))
                        .tracking(-0.6)
                        .foregroundStyle(.axPrimary)
                    if let unit = detail.unit {
                        Text(unit)
                            .font(.axMono(12))
                            .foregroundStyle(.axTertiary)
                    }
                }
                if let delta = detail.delta {
                    Text(delta.text)
                        .font(.axMono(10, .semibold))
                        .tracking(0.6)
                        .foregroundStyle(delta.color)
                }
            }
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
