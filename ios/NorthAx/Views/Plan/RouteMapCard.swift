import SwiftUI
import MapKit

/// GPS route of a completed outdoor workout on real map tiles. The inline map
/// is inert (a pannable map inside a ScrollView steals drags); tapping it opens
/// an interactive full-screen sheet — same behavior as Strava's activity page.
struct RouteMapCard: View {
    let latLng: [[Double]]   // [[lat, lng], …], ≥ 2 pairs (caller-checked)
    let color: Color
    @State private var showFullMap = false

    private var coords: [CLLocationCoordinate2D] {
        latLng.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }
    }

    var body: some View {
        let coords = self.coords
        routeMap(coords)
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
                    routeMap(coords, interactive: true)
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

    private func routeMap(_ coords: [CLLocationCoordinate2D], interactive: Bool = false) -> some View {
        Map(initialPosition: .region(Self.fittedRegion(coords)),
            interactionModes: interactive ? .all : []) {
            MapPolyline(coordinates: coords)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            Annotation("", coordinate: coords.first!) { marker(.axGreen) }
            Annotation("", coordinate: coords.last!) { marker(.axRed) }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .environment(\.colorScheme, .dark)
    }

    private func marker(_ tint: Color) -> some View {
        Circle()
            .fill(tint)
            .frame(width: 8, height: 8)
            .overlay(Circle().stroke(.axBackground, lineWidth: 2))
    }

    /// Region covering the whole route with padding; span floored so a short
    /// loop doesn't zoom in to street level.
    static func fittedRegion(_ coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let lats = coords.map(\.latitude), lngs = coords.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLng = lngs.min()!, maxLng = lngs.max()!
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                           longitude: (minLng + maxLng) / 2),
            span: MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.3, 0.005),
                                   longitudeDelta: max((maxLng - minLng) * 1.3, 0.005))
        )
    }
}
