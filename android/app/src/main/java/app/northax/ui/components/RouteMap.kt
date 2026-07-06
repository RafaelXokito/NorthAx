package app.northax.ui.components

import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
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
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import app.northax.ui.theme.Ax
import kotlin.math.cos
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.util.BoundingBox
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.CustomZoomButtonsController
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Polyline

/**
 * GPS route of a completed outdoor workout on OpenStreetMap tiles. The inline
 * map is inert (a pannable map inside the scrolling sheet steals drags);
 * tapping it opens an interactive full-screen dialog — mirrors iOS.
 */
@Composable
fun RouteMapCard(points: List<List<Double>>, color: Color, modifier: Modifier = Modifier) {
    var showFullMap by remember { mutableStateOf(false) }

    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(180.dp)
            .clip(RoundedCornerShape(12.dp))
            .clickable { showFullMap = true },
    ) {
        RouteMapView(points, color, interactive = false, modifier = Modifier.fillMaxSize())
    }

    if (showFullMap) {
        Dialog(
            onDismissRequest = { showFullMap = false },
            properties = DialogProperties(usePlatformDefaultWidth = false),
        ) {
            Box(modifier = Modifier.fillMaxSize().background(Ax.Background)) {
                RouteMapView(points, color, interactive = true, modifier = Modifier.fillMaxSize())
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

@Composable
private fun RouteMapView(
    points: List<List<Double>>,
    color: Color,
    interactive: Boolean,
    modifier: Modifier = Modifier,
) {
    val geoPoints = remember(points) { points.map { GeoPoint(it[0], it[1]) } }
    var mapView by remember { mutableStateOf<MapView?>(null) }

    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            MapView(ctx).apply {
                setTileSource(TileSourceFactory.MAPNIK)
                setMultiTouchControls(interactive)
                zoomController.setVisibility(CustomZoomButtonsController.Visibility.NEVER)
                if (!interactive) setOnTouchListener { _, _ -> true } // inert; card handles taps
                // Invert luminance so the light OSM tiles match the dark theme.
                overlayManager.tilesOverlay.setColorFilter(darkTileFilter())
                overlays.add(
                    Polyline().apply {
                        setPoints(geoPoints)
                        outlinePaint.apply {
                            this.color = color.toArgb()
                            strokeWidth = 8f
                            strokeCap = Paint.Cap.ROUND
                            strokeJoin = Paint.Join.ROUND
                            isAntiAlias = true
                        }
                    },
                )
                post {
                    zoomToBoundingBox(BoundingBox.fromGeoPoints(geoPoints), false, 48)
                }
                onResume()
                mapView = this
            }
        },
    )
    DisposableEffect(Unit) { onDispose { mapView?.onDetach() } }
}

private fun darkTileFilter() = ColorMatrixColorFilter(
    ColorMatrix(
        floatArrayOf(
            -1f, 0f, 0f, 0f, 255f,
            0f, -1f, 0f, 0f, 255f,
            0f, 0f, -1f, 0f, 255f,
            0f, 0f, 0f, 1f, 0f,
        ),
    ),
)

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
