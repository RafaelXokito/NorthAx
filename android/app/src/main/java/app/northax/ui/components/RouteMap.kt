package app.northax.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import app.northax.ui.theme.Ax
import kotlin.math.cos
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.geometry.LatLngBounds
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.Style
import org.maplibre.android.style.layers.CircleLayer
import org.maplibre.android.style.layers.LineLayer
import org.maplibre.android.style.layers.Property
import org.maplibre.android.style.layers.PropertyFactory.circleColor
import org.maplibre.android.style.layers.PropertyFactory.circleRadius
import org.maplibre.android.style.layers.PropertyFactory.circleStrokeColor
import org.maplibre.android.style.layers.PropertyFactory.circleStrokeWidth
import org.maplibre.android.style.layers.PropertyFactory.lineCap
import org.maplibre.android.style.layers.PropertyFactory.lineColor
import org.maplibre.android.style.layers.PropertyFactory.lineJoin
import org.maplibre.android.style.layers.PropertyFactory.lineOpacity
import org.maplibre.android.style.layers.PropertyFactory.lineWidth
import org.maplibre.geojson.Feature
import org.maplibre.geojson.FeatureCollection
import org.maplibre.geojson.LineString
import org.maplibre.geojson.Point

/**
 * GPS route of a completed outdoor workout on the NorthAx-styled MapLibre map
 * (OpenFreeMap vector tiles, custom dark style in assets/northax-dark.json),
 * with Strava segment paths overlaid. The inline map is inert; tapping it
 * opens an interactive full-screen dialog — mirrors iOS.
 */
@Composable
fun RouteMapCard(
    points: List<List<Double>>,
    segments: List<List<List<Double>>> = emptyList(),
    color: Color,
    modifier: Modifier = Modifier,
) {
    var showFullMap by remember { mutableStateOf(false) }

    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(180.dp)
            .clip(RoundedCornerShape(12.dp)),
    ) {
        RouteMapView(points, segments, color, interactive = false, modifier = Modifier.fillMaxSize())
        // Transparent scrim: the MapView never sees touches; the card just taps.
        Box(
            modifier = Modifier
                .matchParentSize()
                .clickable { showFullMap = true },
        )
    }

    if (showFullMap) {
        Dialog(
            onDismissRequest = { showFullMap = false },
            properties = DialogProperties(usePlatformDefaultWidth = false),
        ) {
            Box(modifier = Modifier.fillMaxSize().background(Ax.Background)) {
                RouteMapView(points, segments, color, interactive = true, modifier = Modifier.fillMaxSize())
                IconButton(
                    onClick = { showFullMap = false },
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(12.dp)
                        .background(Ax.Surface.copy(alpha = 0.85f), RoundedCornerShape(10.dp)),
                ) {
                    Icon(Icons.Filled.Close, contentDescription = "Close", tint = Ax.Primary)
                }
            }
        }
    }
}

/** Small non-interactive map of one path — used by the segment history sheet. */
@Composable
fun SegmentMiniMap(points: List<List<Double>>, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(140.dp)
            .clip(RoundedCornerShape(12.dp)),
    ) {
        RouteMapView(points, emptyList(), Ax.Purple, interactive = false, modifier = Modifier.fillMaxSize())
        Box(modifier = Modifier.matchParentSize()) // swallow touches
    }
}

/** Holds live map objects so recompositions can update the segments overlay. */
private class MapRefs {
    var map: MapLibreMap? = null
    var style: Style? = null
    var lastSegmentCount = -1
}

@Composable
private fun RouteMapView(
    points: List<List<Double>>,
    segments: List<List<List<Double>>>,
    color: Color,
    interactive: Boolean,
    modifier: Modifier = Modifier,
) {
    val lifecycleOwner = LocalLifecycleOwner.current
    val refs = remember { MapRefs() }
    var mapView by remember { mutableStateOf<MapView?>(null) }

    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            MapView(ctx).apply {
                onCreate(null)
                onStart()
                onResume()
                getMapAsync { map ->
                    refs.map = map
                    map.uiSettings.setAllGesturesEnabled(interactive)
                    map.uiSettings.isCompassEnabled = false
                    map.setStyle(Style.Builder().fromUri("asset://northax-dark.json")) { style ->
                        refs.style = style
                        addRouteLayers(style, points, color)
                        setSegments(refs, segments)
                        val bounds = LatLngBounds.Builder()
                            .apply { points.forEach { include(LatLng(it[0], it[1])) } }
                            .build()
                        map.moveCamera(CameraUpdateFactory.newLatLngBounds(bounds, 64))
                    }
                }
                mapView = this
            }
        },
        update = { setSegments(refs, segments) },
    )

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_START -> mapView?.onStart()
                Lifecycle.Event.ON_RESUME -> mapView?.onResume()
                Lifecycle.Event.ON_PAUSE -> mapView?.onPause()
                Lifecycle.Event.ON_STOP -> mapView?.onStop()
                else -> {}
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            mapView?.onPause()
            mapView?.onStop()
            mapView?.onDestroy()
        }
    }
}

/** GeoJSON wants lng,lat — flip from the stored [lat, lng]. */
private fun lineString(path: List<List<Double>>): LineString =
    LineString.fromLngLats(path.map { Point.fromLngLat(it[1], it[0]) })

private fun addRouteLayers(style: Style, points: List<List<Double>>, color: Color) {
    style.addSource(org.maplibre.android.style.sources.GeoJsonSource("route", lineString(points)))
    style.addLayer(
        LineLayer("route-line", "route").withProperties(
            lineColor(color.toArgb()),
            lineWidth(3f),
            lineCap(Property.LINE_CAP_ROUND),
            lineJoin(Property.LINE_JOIN_ROUND),
        ),
    )
    // Strava segment paths sit above the route in a contrasting color.
    style.addSource(org.maplibre.android.style.sources.GeoJsonSource("segments", FeatureCollection.fromFeatures(emptyList())))
    style.addLayer(
        LineLayer("segments-line", "segments").withProperties(
            lineColor(Ax.Purple.toArgb()),
            lineOpacity(0.7f),
            lineWidth(2.5f),
            lineCap(Property.LINE_CAP_ROUND),
            lineJoin(Property.LINE_JOIN_ROUND),
        ),
    )
    val endpoints = FeatureCollection.fromFeatures(
        listOf(
            Feature.fromGeometry(Point.fromLngLat(points.first()[1], points.first()[0])).apply { addStringProperty("kind", "start") },
            Feature.fromGeometry(Point.fromLngLat(points.last()[1], points.last()[0])).apply { addStringProperty("kind", "end") },
        ),
    )
    style.addSource(org.maplibre.android.style.sources.GeoJsonSource("endpoints", endpoints))
    style.addLayer(
        CircleLayer("endpoints-start", "endpoints").withProperties(
            circleColor(Ax.Green.toArgb()),
            circleRadius(4f),
            circleStrokeColor(Ax.Background.toArgb()),
            circleStrokeWidth(2f),
        ).withFilter(org.maplibre.android.style.expressions.Expression.eq(
            org.maplibre.android.style.expressions.Expression.get("kind"),
            org.maplibre.android.style.expressions.Expression.literal("start"),
        )),
    )
    style.addLayer(
        CircleLayer("endpoints-end", "endpoints").withProperties(
            circleColor(Ax.Red.toArgb()),
            circleRadius(4f),
            circleStrokeColor(Ax.Background.toArgb()),
            circleStrokeWidth(2f),
        ).withFilter(org.maplibre.android.style.expressions.Expression.eq(
            org.maplibre.android.style.expressions.Expression.get("kind"),
            org.maplibre.android.style.expressions.Expression.literal("end"),
        )),
    )
}

private fun setSegments(refs: MapRefs, segments: List<List<List<Double>>>) {
    val style = refs.style ?: return
    if (refs.lastSegmentCount == segments.size) return
    refs.lastSegmentCount = segments.size
    val collection = FeatureCollection.fromFeatures(segments.map { Feature.fromGeometry(lineString(it)) })
    style.getSourceAs<org.maplibre.android.style.sources.GeoJsonSource>("segments")?.setGeoJson(collection)
}

/**
 * Tile-less GPS trace for outdoor activities — takes the IconTile slot in
 * [SyncedActivityRow] when the activity carries coarse route points.
 */
@Composable
fun RouteThumbnail(points: List<List<Double>>, color: Color, size: Dp = 36.dp) {
    androidx.compose.foundation.Canvas(
        modifier = Modifier
            .size(size)
            .clip(RoundedCornerShape(10.dp))
            .background(Ax.Inset),
    ) {
        val lats = points.map { it[0] }
        val lngs = points.map { it[1] }
        val minLat = lats.min()
        val maxLat = lats.max()
        val minLng = lngs.min()
        val maxLng = lngs.max()
        // Equirectangular projection: shrink x by cos(midLat) so routes away
        // from the equator aren't horizontally squashed.
        val midLat = Math.toRadians((minLat + maxLat) / 2)
        val w = (maxLng - minLng) * cos(midLat)
        val h = maxLat - minLat
        val inset = 4.dp.toPx()
        val scale = minOf(
            (this.size.width - inset * 2) / maxOf(w, 1e-6).toFloat(),
            (this.size.height - inset * 2) / maxOf(h, 1e-6).toFloat(),
        )
        fun project(p: List<Double>) = androidx.compose.ui.geometry.Offset(
            x = this.size.width / 2 + ((p[1] - (minLng + maxLng) / 2) * cos(midLat) * scale).toFloat(),
            y = this.size.height / 2 - ((p[0] - (minLat + maxLat) / 2) * scale).toFloat(),
        )
        val path = Path()
        val first = project(points[0])
        path.moveTo(first.x, first.y)
        for (p in points.drop(1)) {
            val pt = project(p)
            path.lineTo(pt.x, pt.y)
        }
        drawPath(
            path, color,
            style = Stroke(width = 1.5.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round),
        )
    }
}
