import SwiftUI

/// GPS route of a completed outdoor workout on the NorthAx-styled map, with
/// Strava segment paths overlaid. The inline map is inert (a pannable map
/// inside a ScrollView steals drags); tapping it opens an interactive
/// full-screen sheet — same behavior as Strava's activity page.
struct RouteMapCard: View {
    let latLng: [[Double]]             // [[lat, lng], …], ≥ 2 pairs (caller-checked)
    var segments: [[[Double]]] = []    // segment paths drawn over the route
    let color: Color
    @State private var showFullMap = false

    var body: some View {
        MapLibreMapView(route: latLng, segments: segments, routeColor: color)
            .allowsHitTesting(false)
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.axSecondary)
                    .padding(6)
                    .background(.axSurface.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                    .padding(8)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture { showFullMap = true }
            .sheet(isPresented: $showFullMap) {
                NavigationStack {
                    MapLibreMapView(route: latLng, segments: segments, routeColor: color, interactive: true)
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
