import SwiftUI

/// GPS route of a completed outdoor workout on the NorthAx-styled map. The
/// inline map is inert (a pannable map inside a ScrollView steals drags);
/// tapping it opens an interactive full-screen sheet — same behavior as
/// Strava's activity page. Segment paths live in the per-segment sheet.
struct RouteMapCard: View {
    let latLng: [[Double]]   // [[lat, lng], …], ≥ 2 pairs (caller-checked)
    var highlights: [MapHighlight] = []   // where BEST/2nd/3rd/KOM were hit
    let color: Color
    var onHighlightTap: ((String) -> Void)? = nil   // badge tap → segment overview
    @State private var showFullMap = false

    var body: some View {
        MapLibreMapView(route: latLng, routeColor: color, highlights: highlights,
                        onHighlightTap: onHighlightTap,
                        onMapTap: { showFullMap = true })
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.axSecondary)
                    .padding(6)
                    .background(.axSurface.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                    .padding(8)
                    .allowsHitTesting(false)
            }
            .sheet(isPresented: $showFullMap) {
                NavigationStack {
                    MapLibreMapView(route: latLng, routeColor: color, highlights: highlights, interactive: true,
                                    onHighlightTap: { segmentId in
                                        // Dismiss this sheet first; present the overview
                                        // once the dismissal settles.
                                        showFullMap = false
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                            onHighlightTap?(segmentId)
                                        }
                                    })
                        .ignoresSafeArea(edges: .bottom)
                        .navigationTitle("Route")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showFullMap = false }
                            }
                        }
                }
                .preferredColorScheme(.dark)
            }
    }
}
