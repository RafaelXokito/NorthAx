import SwiftUI

/// Settings → Integrations → Data Priority. Lets the user choose which source
/// wins for each metric when more than one integration reports it
/// (see docs/multi-source-metrics.md). Defaults preserve current behavior
/// (intervals.icu first), so nothing changes until the user reorders.
struct MetricPriorityView: View {
    @Environment(AthleteStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("When more than one integration reports the same metric, NorthAx uses the value from your preferred source. Sources that can't provide a metric are skipped automatically.")
                    .font(.subheadline)
                    .foregroundStyle(.axSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("WELLNESS METRICS")
                    ForEach(MergeableMetric.allCases) { metric in
                        row(metric)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("ACTIVITY DATA")
                    Text("When the same workout is imported from more than one source, NorthAx keeps the one from your preferred source.")
                        .font(.caption)
                        .foregroundStyle(.axTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    activityRow
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color.axBackground)
        .navigationTitle("Data Priority")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .scrollIndicators(.hidden)
    }

    private var activityRow: some View {
        let current = store.activityPriority.primary
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Preferred activity source")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Primary: \(current.displayName)")
                    .font(.caption)
                    .foregroundStyle(.axSecondary)
            }

            Spacer()

            Menu {
                ForEach(ActivitySource.allCases) { src in
                    Button {
                        store.activityPriority.setPrimary(src)
                    } label: {
                        if src == current {
                            Label(src.displayName, systemImage: "checkmark")
                        } else {
                            Text(src.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(current.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.axAccent)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.bold())
                        .foregroundStyle(.axTertiary)
                }
            }
        }
        .padding(16)
        .background(Color.axSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.axBorder, lineWidth: 1))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.axTertiary).tracking(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ metric: MergeableMetric) -> some View {
        let current = store.metricPriority.sources(for: metric).first ?? metric.candidateSources.first!
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(metric.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Primary: \(current.displayName)")
                    .font(.caption)
                    .foregroundStyle(.axSecondary)
            }

            Spacer()

            Menu {
                ForEach(metric.candidateSources) { src in
                    Button {
                        store.metricPriority.setPrimary(src, for: metric)
                    } label: {
                        if src == current {
                            Label(src.displayName, systemImage: "checkmark")
                        } else {
                            Text(src.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(current.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.axAccent)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.bold())
                        .foregroundStyle(.axTertiary)
                }
            }
        }
        .padding(16)
        .background(Color.axSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.axBorder, lineWidth: 1))
    }
}

#Preview {
    NavigationStack {
        MetricPriorityView()
            .environment(AthleteStore())
    }
}
