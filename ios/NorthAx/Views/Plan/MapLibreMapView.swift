import SwiftUI
import MapLibre

/// A ranked-segment marker on the route map: where a BEST/2nd/3rd/KOM was hit.
struct MapHighlight: Equatable {
    enum Kind: CaseIterable { case best, second, third, kom }
    let point: [Double]   // [lat, lng] — the segment's start
    let kind: Kind
    var segmentId: String = ""   // tap target → segment overview

    var color: Color {
        switch kind {
        case .best: return .axAccent
        case .second, .third: return .axAmber
        case .kom: return .axPurple
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
    var onHighlightTap: ((String) -> Void)? = nil   // segmentId of a tapped badge
    var onMapTap: (() -> Void)? = nil               // non-badge tap on an inert map

    func makeUIView(context: Context) -> MLNMapView {
        let styleURL = Bundle.main.url(forResource: "northax-dark", withExtension: "json")
        let mapView = MLNMapView(frame: .zero, styleURL: styleURL)
        mapView.delegate = context.coordinator
        mapView.compassView.isHidden = true
        // Chrome: no wordmark anywhere; the OSM attribution (license
        // requirement) stays as the small ⓘ on the full-screen map only.
        mapView.logoView.isHidden = true
        mapView.attributionButton.isHidden = !interactive
        if !interactive {
            // Inert but still tappable: kill camera gestures, keep touch alive
            // so highlight badges can be hit-tested.
            mapView.allowsScrolling = false
            mapView.allowsZooming = false
            mapView.allowsRotating = false
            mapView.allowsTilting = false
        }
        mapView.addGestureRecognizer(
            UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        )
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
            // Dark casing under the route so it pops off roads of similar hue.
            let casingLayer = MLNLineStyleLayer(identifier: "route-casing", source: routeSource)
            casingLayer.lineColor = NSExpression(forConstantValue: UIColor(Color.axBackground))
            casingLayer.lineWidth = NSExpression(forConstantValue: 6)
            casingLayer.lineOpacity = NSExpression(forConstantValue: 0.85)
            casingLayer.lineCap = NSExpression(forConstantValue: "round")
            casingLayer.lineJoin = NSExpression(forConstantValue: "round")
            style.addLayer(casingLayer)
            let routeLayer = MLNLineStyleLayer(identifier: "route-line", source: routeSource)
            routeLayer.lineColor = NSExpression(forConstantValue: UIColor(parent.routeColor))
            routeLayer.lineWidth = NSExpression(forConstantValue: 3.5)
            routeLayer.lineCap = NSExpression(forConstantValue: "round")
            routeLayer.lineJoin = NSExpression(forConstantValue: "round")
            style.addLayer(routeLayer)

            addCircleLayer(id: "endpoint-start", point: route.first, color: .axGreen, radius: 4, to: style)
            addCircleLayer(id: "endpoint-end", point: route.last, color: .axRed, radius: 4, to: style)

            // One source + icon layer per highlight kind (pin badges with a
            // drawn star/digit/crown, rendered at runtime — the style ships no
            // sprite sheet); shapes filled by updateHighlights. The pin's tip
            // marks the segment start, so icons anchor at the bottom.
            for kind in MapHighlight.Kind.allCases {
                style.setImage(Self.pinImage(for: kind), forName: "highlight-\(kind)")
                let source = MLNShapeSource(identifier: "highlight-\(kind)", shapes: [])
                style.addSource(source)
                highlightSources[kind] = source
                let layer = MLNSymbolStyleLayer(identifier: "highlight-\(kind)-icon", source: source)
                layer.iconImageName = NSExpression(forConstantValue: "highlight-\(kind)")
                layer.iconAnchor = NSExpression(forConstantValue: "bottom")
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
                    f.attributes = ["segmentId": h.segmentId]
                    return f
                }
                highlightSources[kind]?.shape = MLNShapeCollectionFeature(shapes: features)
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MLNMapView else { return }
            let point = gesture.location(in: mapView)
            let hitRect = CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
            let layerIds = Set(MapHighlight.Kind.allCases.map { "highlight-\($0)-icon" })
            let tapped = mapView.visibleFeatures(in: hitRect, styleLayerIdentifiers: layerIds)
                .compactMap { $0.attribute(forKey: "segmentId") as? String }
                .first
            if let tapped, !tapped.isEmpty {
                parent.onHighlightTap?(tapped)
            } else if !parent.interactive {
                parent.onMapTap?()
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

        /// 26×34pt teardrop map pin in the kind's color; the head carries a
        /// path-drawn star (BEST), crown (KOM), or a bold digit (2nd/3rd).
        /// Geometry mirrors the Android renderer so both apps match.
        static func pinImage(for kind: MapHighlight.Kind) -> UIImage {
            let color = UIColor(MapHighlight(point: [], kind: kind).color)
            let outline = UIColor(Color.axBackground)
            return UIGraphicsImageRenderer(size: CGSize(width: 26, height: 34)).image { _ in
                let tail = UIBezierPath()
                tail.move(to: CGPoint(x: 7.5, y: 19.5))
                tail.addLine(to: CGPoint(x: 13, y: 32.5))
                tail.addLine(to: CGPoint(x: 18.5, y: 19.5))
                tail.close()
                color.setFill()
                tail.fill()
                outline.setStroke()
                tail.lineWidth = 1.5
                tail.stroke()

                let head = UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: 22, height: 22))
                color.setFill()
                head.fill()
                head.lineWidth = 2
                head.stroke()

                UIColor.white.setFill()
                switch kind {
                case .best:
                    star(center: CGPoint(x: 13, y: 13), outer: 6.5, inner: 2.7).fill()
                case .kom:
                    crown(center: CGPoint(x: 13, y: 13)).fill()
                case .second, .third:
                    let digit = NSAttributedString(string: kind == .second ? "2" : "3", attributes: [
                        .font: UIFont.systemFont(ofSize: 12.5, weight: .heavy),
                        .foregroundColor: UIColor.white,
                    ])
                    let s = digit.size()
                    digit.draw(at: CGPoint(x: 13 - s.width / 2, y: 13 - s.height / 2))
                }
            }
        }

        private static func star(center: CGPoint, outer: CGFloat, inner: CGFloat) -> UIBezierPath {
            let path = UIBezierPath()
            for i in 0..<10 {
                let angle = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
                let radius = i.isMultiple(of: 2) ? outer : inner
                let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                i == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            path.close()
            return path
        }

        private static func crown(center c: CGPoint) -> UIBezierPath {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: c.x - 5.5, y: c.y + 4.5))       // base left
            path.addLine(to: CGPoint(x: c.x - 5.5, y: c.y - 1.5))    // left spike
            path.addLine(to: CGPoint(x: c.x - 2.7, y: c.y + 0.8))
            path.addLine(to: CGPoint(x: c.x, y: c.y - 4))            // middle spike
            path.addLine(to: CGPoint(x: c.x + 2.7, y: c.y + 0.8))
            path.addLine(to: CGPoint(x: c.x + 5.5, y: c.y - 1.5))    // right spike
            path.addLine(to: CGPoint(x: c.x + 5.5, y: c.y + 4.5))    // base right
            path.close()
            return path
        }

        private static func polyline(_ path: [[Double]]) -> MLNPolylineFeature {
            var coords = path.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }
            return MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))
        }
    }
}
