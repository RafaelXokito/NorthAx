import SwiftUI
import MapLibre

/// NorthAx-styled MapLibre map (OpenFreeMap vector tiles, custom dark style in
/// Resources/northax-dark.json) rendering one GPS path with start/finish dots.
/// Used by the route card, its full-screen sheet, and the segment mini map.
struct MapLibreMapView: UIViewRepresentable {
    let route: [[Double]]              // [[lat, lng], …], ≥ 2 pairs
    let routeColor: Color
    var interactive: Bool = false

    func makeUIView(context: Context) -> MLNMapView {
        let styleURL = Bundle.main.url(forResource: "northax-dark", withExtension: "json")
        let mapView = MLNMapView(frame: .zero, styleURL: styleURL)
        mapView.delegate = context.coordinator
        mapView.isUserInteractionEnabled = interactive
        mapView.compassView.isHidden = true
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    static func bounds(of coords: [[Double]]) -> MLNCoordinateBounds {
        let lats = coords.map { $0[0] }, lngs = coords.map { $0[1] }
        return MLNCoordinateBounds(
            sw: CLLocationCoordinate2D(latitude: lats.min() ?? 0, longitude: lngs.min() ?? 0),
            ne: CLLocationCoordinate2D(latitude: lats.max() ?? 0, longitude: lngs.max() ?? 0)
        )
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: MapLibreMapView

        init(_ parent: MapLibreMapView) { self.parent = parent }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            let route = parent.route
            let routeSource = MLNShapeSource(identifier: "route", shape: Self.polyline(route))
            style.addSource(routeSource)
            let routeLayer = MLNLineStyleLayer(identifier: "route-line", source: routeSource)
            routeLayer.lineColor = NSExpression(forConstantValue: UIColor(parent.routeColor))
            routeLayer.lineWidth = NSExpression(forConstantValue: 3)
            routeLayer.lineCap = NSExpression(forConstantValue: "round")
            routeLayer.lineJoin = NSExpression(forConstantValue: "round")
            style.addLayer(routeLayer)

            addEndpoint(route.first, color: .axGreen, id: "start", to: style)
            addEndpoint(route.last, color: .axRed, id: "end", to: style)

            // Fit the camera HERE, not in makeUIView: before layout the view
            // has zero size and MapLibre computes a far-too-low zoom.
            mapView.setVisibleCoordinateBounds(
                MapLibreMapView.bounds(of: route),
                edgePadding: .init(top: 32, left: 32, bottom: 32, right: 32),
                animated: false
            )
        }

        private func addEndpoint(_ point: [Double]?, color: Color, id: String, to style: MLNStyle) {
            guard let point else { return }
            let feature = MLNPointFeature()
            feature.coordinate = CLLocationCoordinate2D(latitude: point[0], longitude: point[1])
            let source = MLNShapeSource(identifier: "endpoint-\(id)", shape: feature)
            style.addSource(source)
            let layer = MLNCircleStyleLayer(identifier: "endpoint-\(id)-circle", source: source)
            layer.circleColor = NSExpression(forConstantValue: UIColor(color))
            layer.circleRadius = NSExpression(forConstantValue: 4)
            layer.circleStrokeColor = NSExpression(forConstantValue: UIColor(Color.axBackground))
            layer.circleStrokeWidth = NSExpression(forConstantValue: 2)
            style.addLayer(layer)
        }

        private static func polyline(_ path: [[Double]]) -> MLNPolylineFeature {
            var coords = path.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }
            return MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))
        }
    }
}
