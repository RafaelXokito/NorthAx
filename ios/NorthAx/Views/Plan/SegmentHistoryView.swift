import SwiftUI

/// The athlete's effort history on one Strava segment (§13), newest first,
/// with the all-time best highlighted.
struct SegmentHistoryView: View {
    let segment: SegmentEffort
    @Environment(AthleteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var history: SegmentHistory?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if let pts = segment.points ?? history?.points, pts.count > 1 {
                        MapLibreMapView(route: pts, routeColor: .axPurple)
                            .frame(height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .allowsHitTesting(false)
                    }
                    if let history {
                        effortsCard(history)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                }
                .padding(20)
            }
            .background(Color.axBackground)
            .navigationTitle("Segment")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { history = await store.segmentHistory(for: segment.segmentId) }
        }
    }

    private var header: some View {
        AxCard(radius: 18, padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(segment.name)
                    .font(.axDisplay(20, .heavy))
                    .foregroundStyle(.axPrimary)
                Text(segment.metaLine)
                    .font(.axMono(11))
                    .tracking(0.6)
                    .foregroundStyle(.axSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func effortsCard(_ history: SegmentHistory) -> some View {
        AxCard(radius: 18, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("EFFORTS")
                VStack(spacing: 8) {
                    ForEach(history.efforts) { effort in
                        effortRow(effort, isBest: effort.elapsedSeconds == history.bestElapsedSeconds)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func effortRow(_ effort: SegmentEffort, isBest: Bool) -> some View {
        HStack(spacing: 10) {
            Text(effort.startDate.formatted(date: .abbreviated, time: .omitted).uppercased())
                .font(.axMono(10))
                .tracking(0.4)
                .foregroundStyle(.axTertiary)
            Spacer()
            Text(effort.formattedTime)
                .font(.axMono(12, .semibold))
                .foregroundStyle(isBest ? .axAccent : .axPrimary)
            if isBest { AxPill(text: "BEST", color: .axAccent) }
        }
        .padding(12)
        .background(Color.axInset)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
