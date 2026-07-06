import SwiftUI
import MapLibre

/// A ranked-segment marker on the route map: where a BEST/2nd/3rd/KOM was hit.
struct MapHighlight: Equatable {
    enum Kind: CaseIterable { case best, second, third, kom }
    let point: [Double]   // [lat, lng] — the segment's start
    let kind: Kind

    var color: Color {
        switch kind {
        case .best: return .axAccent
        case .second, .third: return .axAmber
        case .kom: return .axPurple
        }
    }

    /// Badge glyph — unicode so iOS and Android render the same marks.
    var glyph: String {
        switch kind {
        case .best: return "★"
        case .second: return "2"
        case .third: return "3"
        case .kom: return "♛"
        }
    }
}

/// NorthAx-styled MapLibre map (OpenFreeMap vector tiles, custom dark style in
/// Resources/northax-dark.json) rendering one GPS path with start/finish dots
/// and optional ranked-segment highlight markers. Used by the route card, its
/// full-screen sheet, and the segment mini map.
struct MapLibreMapView: UIViewRepresentable {
    let route: [[Double]]              // [[lat, lng], …], ≥ 2 pairs
    let routeColor: Color
    var highlights: [MapHighlight] = []
    var interactive: Bool = false

    func makeUIView(context: Context) -> MLNMapView {
        let styleURL = Bundle.main.url(forResource: "northax-dark", withExtension: "json")
        let mapView = MLNMapView(frame: .zero, styleURL: styleURL)
        mapView.delegate = context.coordinator
        mapView.isUserInteractionEnabled = interactive
        mapView.compassView.isHidden = true
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateHighlights()   // segments load after the map
    }

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
        private var highlightSources: [MapHighlight.Kind: MLNShapeSource] = [:]
        private var renderedHighlights: [MapHighlight]?

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

            addCircleLayer(id: "endpoint-start", point: route.first, color: .axGreen, radius: 4, to: style)
            addCircleLayer(id: "endpoint-end", point: route.last, color: .axRed, radius: 4, to: style)

            // One source + icon layer per highlight kind (★ / 2 / 3 / ♛ badges,
            // rendered at runtime — the style ships no sprite sheet); shapes
            // filled by updateHighlights.
            for kind in MapHighlight.Kind.allCases {
                let sample = MapHighlight(point: [], kind: kind)
                style.setImage(Self.badgeImage(color: UIColor(sample.color), glyph: sample.glyph),
                               forName: "highlight-\(kind)")
                let source = MLNShapeSource(identifier: "highlight-\(kind)", shapes: [])
                style.addSource(source)
                highlightSources[kind] = source
                let layer = MLNSymbolStyleLayer(identifier: "highlight-\(kind)-icon", source: source)
                layer.iconImageName = NSExpression(forConstantValue: "highlight-\(kind)")
                layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
                layer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
                style.addLayer(layer)
            }
            renderedHighlights = nil
            updateHighlights()

            // Fit the camera HERE, not in makeUIView: before layout the view
            // has zero size and MapLibre computes a far-too-low zoom.
            mapView.setVisibleCoordinateBounds(
                MapLibreMapView.bounds(of: route),
                edgePadding: .init(top: 32, left: 32, bottom: 32, right: 32),
                animated: false
            )
        }

        func updateHighlights() {
            guard !highlightSources.isEmpty, renderedHighlights != parent.highlights else { return }
            renderedHighlights = parent.highlights
            for kind in MapHighlight.Kind.allCases {
                let features = parent.highlights.filter { $0.kind == kind }.map { h -> MLNPointFeature in
                    let f = MLNPointFeature()
                    f.coordinate = CLLocationCoordinate2D(latitude: h.point[0], longitude: h.point[1])
                    return f
                }
                highlightSources[kind]?.shape = MLNShapeCollectionFeature(shapes: features)
            }
        }

        private func addCircleLayer(id: String, point: [Double]?, color: Color, radius: Double, to style: MLNStyle) {
            guard let point else { return }
            let feature = MLNPointFeature()
            feature.coordinate = CLLocationCoordinate2D(latitude: point[0], longitude: point[1])
            let source = MLNShapeSource(identifier: id, shape: feature)
            style.addSource(source)
            let layer = MLNCircleStyleLayer(identifier: "\(id)-circle", source: source)
            layer.circleColor = NSExpression(forConstantValue: UIColor(color))
            layer.circleRadius = NSExpression(forConstantValue: radius)
            layer.circleStrokeColor = NSExpression(forConstantValue: UIColor(Color.axBackground))
            layer.circleStrokeWidth = NSExpression(forConstantValue: 2)
            style.addLayer(layer)
        }

        /// 22pt circular badge in the kind's color with a centered glyph.
        static func badgeImage(color: UIColor, glyph: String) -> UIImage {
            let size = CGSize(width: 22, height: 22)
            return UIGraphicsImageRenderer(size: size).image { _ in
                let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
                let circle = UIBezierPath(ovalIn: rect)
                color.setFill()
                circle.fill()
                UIColor(Color.axBackground).setStroke()
                circle.lineWidth = 2
                circle.stroke()
                let text = NSAttributedString(string: glyph, attributes: [
                    .font: UIFont.systemFont(ofSize: 11, weight: .bold),
                    .foregroundColor: UIColor.white,
                ])
                let textSize = text.size()
                text.draw(at: CGPoint(x: (size.width - textSize.width) / 2,
                                      y: (size.height - textSize.height) / 2))
            }
        }

        private static func polyline(_ path: [[Double]]) -> MLNPolylineFeature {
            var coords = path.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }
            return MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))
        }
    }
}
