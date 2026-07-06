package app.northax.ui.screens.plan

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.northax.domain.model.SegmentEffort
import app.northax.domain.model.SegmentHistory
import app.northax.store.AthleteStore
import app.northax.ui.components.AxCard
import app.northax.ui.components.AxPill
import app.northax.ui.components.AxSheet
import app.northax.ui.components.SectionLabel
import app.northax.ui.components.SegmentMiniMap
import app.northax.ui.theme.Ax
import app.northax.ui.theme.axDisplay
import app.northax.ui.theme.axMono
import app.northax.ui.theme.tracked
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** The athlete's effort history on one Strava segment (§13), newest first,
 *  with the all-time best highlighted — the SegmentHistoryView port. */
@Composable
fun SegmentHistorySheet(store: AthleteStore, segment: SegmentEffort, onDismiss: () -> Unit) {
    var history by remember { mutableStateOf<SegmentHistory?>(null) }

    LaunchedEffect(segment.segmentId) {
        history = store.segmentHistory(segment.segmentId)
    }

    AxSheet(onDismiss = onDismiss, title = "Segment") {
        Column(
            verticalArrangement = Arrangement.spacedBy(18.dp),
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 32.dp),
        ) {
            AxCard(modifier = Modifier.fillMaxWidth()) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(segment.name, style = axDisplay(20, FontWeight.Black), color = Ax.Primary)
                    Text(segment.metaLine, style = axMono(11).tracked(0.6), color = Ax.Secondary)
                }
            }

            (segment.points ?: history?.points)?.takeIf { it.size > 1 }?.let { pts ->
                SegmentMiniMap(points = pts)
            }

            history?.let { h ->
                AxCard(modifier = Modifier.fillMaxWidth()) {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        SectionLabel("Efforts")
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            h.efforts.forEach { effort ->
                                EffortRow(effort, isBest = effort.elapsedSeconds == h.bestElapsedSeconds)
                            }
                        }
                    }
                }
            } ?: Row(
                horizontalArrangement = Arrangement.Center,
                modifier = Modifier.fillMaxWidth().padding(top = 40.dp),
            ) {
                CircularProgressIndicator(color = Ax.Accent)
            }
        }
    }
}

private val dateFormat = DateTimeFormatter.ofPattern("d MMM yyyy", Locale.US)

@Composable
private fun EffortRow(effort: SegmentEffort, isBest: Boolean) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(Ax.Inset)
            .padding(12.dp),
    ) {
        Text(
            dateFormat.format(effort.startDate.atZone(ZoneId.systemDefault())).uppercase(),
            style = axMono(10).tracked(0.4),
            color = Ax.Tertiary,
            modifier = Modifier.weight(1f),
        )
        Text(
            effort.formattedTime,
            style = axMono(12, FontWeight.SemiBold),
            color = if (isBest) Ax.Accent else Ax.Primary,
        )
        if (isBest) AxPill("BEST", Ax.Accent)
    }
}
