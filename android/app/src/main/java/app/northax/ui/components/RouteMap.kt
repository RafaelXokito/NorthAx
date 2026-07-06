package app.northax.ui.components

import android.graphics.Paint
import android.graphics.RectF
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
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
import androidx.compose.ui.input.pointer.pointerInput
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
import org.maplibre.android.style.layers.PropertyFactory.iconAllowOverlap
import org.maplibre.android.style.layers.PropertyFactory.iconAnchor
import org.maplibre.android.style.layers.PropertyFactory.iconIgnorePlacement
import org.maplibre.android.style.layers.PropertyFactory.iconImage
import org.maplibre.android.style.layers.PropertyFactory.circleColor
import org.maplibre.android.style.layers.PropertyFactory.circleRadius
import org.maplibre.android.style.layers.PropertyFactory.circleStrokeColor
import org.maplibre.android.style.layers.PropertyFactory.circleStrokeWidth
import org.maplibre.android.style.layers.PropertyFactory.lineCap
import org.maplibre.android.style.layers.PropertyFactory.lineColor
import org.maplibre.android.style.layers.PropertyFactory.lineJoin
import org.maplibre.android.style.layers.PropertyFactory.lineOpacity
import org.maplibre.android.style.layers.PropertyFactory.lineWidth
import org.maplibre.android.style.layers.SymbolLayer
import org.maplibre.geojson.Feature
import org.maplibre.geojson.FeatureCollection
import org.maplibre.geojson.LineString
import org.maplibre.geojson.Point

/** A ranked-segment marker on the route map: where a BEST/2nd/3rd/KOM was hit. */
data class MapHighlight(val point: List<Double>, val kind: Kind, val segmentId: String = "") {
    enum class Kind { Best, Second, Third, Kom }

    val color: Color
        get() = when (kind) {
            Kind.Best -> Ax.Accent
            Kind.Second, Kind.Third -> Ax.Amber
            Kind.Kom -> Ax.Purple
        }
}

/**
 * GPS route of a completed outdoor workout on the NorthAx-styled MapLibre map
 * (OpenFreeMap vector tiles, custom dark style in assets/northax-dark.json),
 * with markers where this ride hit ranked segment results. The inline map is
 * inert; tapping it opens an interactive full-screen dialog — mirrors iOS.
 */
@Composable
fun RouteMapCard(
    points: List<List<Double>>,
    color: Color,
    highlights: List<MapHighlight> = emptyList(),
    onHighlightTap: ((String) -> Unit)? = null,   // badge tap → segment overview
    modifier: Modifier = Modifier,
) {
    var showFullMap by remember { mutableStateOf(false) }
    val inlineRefs = remember { MapRefs() }

    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(180.dp)
            .clip(RoundedCornerShape(12.dp)),
    ) {
        RouteMapView(points, color, highlights, inlineRefs, interactive = false, modifier = Modifier.fillMaxSize())
        // Transparent scrim: the MapView never sees touches; the scrim hit-tests
        // highlight badges and otherwise opens the full-screen map.
        Box(
            modifier = Modifier
                .matchParentSize()
                .pointerInput(onHighlightTap) {
                    detectTapGestures { offset ->
                        val segmentId = inlineRefs.hitTestHighlight(offset.x, offset.y)
                        if (segmentId != null && onHighlightTap != null) {
                            onHighlightTap(segmentId)
                        } else {
                            showFullMap = true
                        }
                    }
                },
        )
    }

    if (showFullMap) {
        val fullRefs = remember { MapRefs() }
        Dialog(
            onDismissRequest = { showFullMap = false },
            properties = DialogProperties(usePlatformDefaultWidth = false),
        ) {
            Box(modifier = Modifier.fillMaxSize().background(Ax.Background)) {
                RouteMapView(
                    points, color, highlights, fullRefs, interactive = true,
                    onHighlightTap = { segmentId ->
                        showFullMap = false
                        onHighlightTap?.invoke(segmentId)
                    },
                    modifier = Modifier.fillMaxSize(),
                )
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
        RouteMapView(points, Ax.Purple, emptyList(), remember { MapRefs() }, interactive = false, modifier = Modifier.fillMaxSize())
        Box(modifier = Modifier.matchParentSize()) // swallow touches
    }
}

/** Holds the live map/style so recompositions can update markers + hit-test taps. */
private class MapRefs {
    var map: MapLibreMap? = null
    var style: Style? = null
    var renderedHighlights: List<MapHighlight>? = null

    /** The segmentId of a highlight badge near (x, y) screen px, if any. */
    fun hitTestHighlight(x: Float, y: Float): String? {
        val m = map ?: return null
        val rect = RectF(x - 48f, y - 48f, x + 48f, y + 48f)
        val layers = MapHighlight.Kind.entries.map { "highlight-${it.name}-icon" }.toTypedArray()
        return m.queryRenderedFeatures(rect, *layers).firstOrNull()
            ?.getStringProperty("segmentId")?.takeIf { it.isNotEmpty() }
    }
}

@Composable
private fun RouteMapView(
    points: List<List<Double>>,
    color: Color,
    highlights: List<MapHighlight>,
    refs: MapRefs,
    interactive: Boolean,
    onHighlightTap: ((String) -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val lifecycleOwner = LocalLifecycleOwner.current
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
                    // Chrome: no wordmark anywhere; the OSM attribution (license
                    // requirement) stays as the small ⓘ on the full-screen map only.
                    map.uiSettings.isLogoEnabled = false
                    map.uiSettings.isAttributionEnabled = interactive
                    if (interactive && onHighlightTap != null) {
                        map.addOnMapClickListener { latLng ->
                            val p = map.projection.toScreenLocation(latLng)
                            refs.hitTestHighlight(p.x, p.y)?.let { onHighlightTap(it); true } ?: false
                        }
                    }
                    map.setStyle(Style.Builder().fromUri("asset://northax-dark.json")) { style ->
                        refs.style = style
                        addRouteLayers(style, points, color, resources.displayMetrics.density)
                        setHighlights(refs, highlights)
                        val bounds = LatLngBounds.Builder()
                            .apply { points.forEach { include(LatLng(it[0], it[1])) } }
                            .build()
                        // post: fit the camera only after the view is laid out —
                        // against a zero-size view the zoom lands far too low.
                        post { map.moveCamera(CameraUpdateFactory.newLatLngBounds(bounds, 64)) }
                    }
                }
                mapView = this
            }
        },
        update = { setHighlights(refs, highlights) },   // segments load after the map
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

/**
 * 26×34dp teardrop map pin in the kind's color; the head carries a path-drawn
 * star (BEST), crown (KOM), or a bold digit (2nd/3rd). Geometry mirrors the
 * iOS renderer so both apps match.
 */
private fun pinBitmap(kind: MapHighlight.Kind, density: Float): android.graphics.Bitmap {
    fun d(v: Float) = v * density
    val bitmap = android.graphics.Bitmap.createBitmap(d(26f).toInt(), d(34f).toInt(), android.graphics.Bitmap.Config.ARGB_8888)
    val canvas = android.graphics.Canvas(bitmap)
    val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = MapHighlight(emptyList(), kind).color.toArgb() }
    val outline = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Ax.Background.toArgb()
        style = Paint.Style.STROKE
        strokeWidth = d(2f)
    }

    val tail = android.graphics.Path().apply {
        moveTo(d(7.5f), d(19.5f))
        lineTo(d(13f), d(32.5f))
        lineTo(d(18.5f), d(19.5f))
        close()
    }
    canvas.drawPath(tail, fill)
    canvas.drawPath(tail, Paint(outline).apply { strokeWidth = d(1.5f) })

    canvas.drawCircle(d(13f), d(13f), d(11f), fill)
    canvas.drawCircle(d(13f), d(13f), d(11f), outline)

    val white = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = android.graphics.Color.WHITE }
    when (kind) {
        MapHighlight.Kind.Best -> canvas.drawPath(starPath(d(13f), d(13f), d(6.5f), d(2.7f)), white)
        MapHighlight.Kind.Kom -> canvas.drawPath(crownPath(d(13f), d(13f), density), white)
        MapHighlight.Kind.Second, MapHighlight.Kind.Third -> {
            val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = android.graphics.Color.WHITE
                textSize = d(12.5f)
                typeface = android.graphics.Typeface.create(android.graphics.Typeface.DEFAULT_BOLD, android.graphics.Typeface.BOLD)
                textAlign = Paint.Align.CENTER
            }
            val glyph = if (kind == MapHighlight.Kind.Second) "2" else "3"
            canvas.drawText(glyph, d(13f), d(13f) - (text.descent() + text.ascent()) / 2, text)
        }
    }
    return bitmap
}

private fun starPath(cx: Float, cy: Float, outer: Float, inner: Float): android.graphics.Path {
    val path = android.graphics.Path()
    for (i in 0 until 10) {
        val angle = -Math.PI / 2 + i * Math.PI / 5
        val radius = if (i % 2 == 0) outer else inner
        val x = cx + (kotlin.math.cos(angle) * radius).toFloat()
        val y = cy + (kotlin.math.sin(angle) * radius).toFloat()
        if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
    }
    path.close()
    return path
}

private fun crownPath(cx: Float, cy: Float, density: Float): android.graphics.Path {
    fun d(v: Float) = v * density
    return android.graphics.Path().apply {
        moveTo(cx - d(5.5f), cy + d(4.5f))   // base left
        lineTo(cx - d(5.5f), cy - d(1.5f))   // left spike
        lineTo(cx - d(2.7f), cy + d(0.8f))
        lineTo(cx, cy - d(4f))               // middle spike
        lineTo(cx + d(2.7f), cy + d(0.8f))
        lineTo(cx + d(5.5f), cy - d(1.5f))   // right spike
        lineTo(cx + d(5.5f), cy + d(4.5f))   // base right
        close()
    }
}

private fun addRouteLayers(style: Style, points: List<List<Double>>, color: Color, density: Float) {
    style.addSource(org.maplibre.android.style.sources.GeoJsonSource("route", lineString(points)))
    // Dark casing under the route so it pops off roads of similar hue.
    style.addLayer(
        LineLayer("route-casing", "route").withProperties(
            lineColor(Ax.Background.toArgb()),
            lineWidth(6f),
            lineOpacity(0.85f),
            lineCap(Property.LINE_CAP_ROUND),
            lineJoin(Property.LINE_JOIN_ROUND),
        ),
    )
    style.addLayer(
        LineLayer("route-line", "route").withProperties(
            lineColor(color.toArgb()),
            lineWidth(3.5f),
            lineCap(Property.LINE_CAP_ROUND),
            lineJoin(Property.LINE_JOIN_ROUND),
        ),
    )
    // One source + icon layer per highlight kind (pin badges with a drawn
    // star/digit/crown, rendered at runtime — the style ships no sprite
    // sheet); features filled by setHighlights. The pin's tip marks the
    // segment start, so icons anchor at the bottom.
    for (kind in MapHighlight.Kind.entries) {
        val id = "highlight-${kind.name}"
        style.addImage(id, pinBitmap(kind, density))
        style.addSource(org.maplibre.android.style.sources.GeoJsonSource(id, FeatureCollection.fromFeatures(emptyList())))
        style.addLayer(
            SymbolLayer("$id-icon", id).withProperties(
                iconImage(id),
                iconAnchor(Property.ICON_ANCHOR_BOTTOM),
                iconAllowOverlap(true),
                iconIgnorePlacement(true),
            ),
        )
    }
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

private fun setHighlights(refs: MapRefs, highlights: List<MapHighlight>) {
    val style = refs.style ?: return
    if (refs.renderedHighlights == highlights) return
    refs.renderedHighlights = highlights
    for (kind in MapHighlight.Kind.entries) {
        val features = highlights.filter { it.kind == kind }.map { h ->
            Feature.fromGeometry(Point.fromLngLat(h.point[1], h.point[0]))
                .apply { addStringProperty("segmentId", h.segmentId) }
        }
        style.getSourceAs<org.maplibre.android.style.sources.GeoJsonSource>("highlight-${kind.name}")
            ?.setGeoJson(FeatureCollection.fromFeatures(features))
    }
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
