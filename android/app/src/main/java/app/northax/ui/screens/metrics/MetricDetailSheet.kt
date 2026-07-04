package app.northax.ui.screens.metrics

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.northax.ui.components.AxSegmented
import app.northax.ui.components.AxSheet
import app.northax.ui.components.MetricLineChart
import app.northax.ui.theme.Ax
import app.northax.ui.theme.axDisplay
import app.northax.ui.theme.axMono
import app.northax.ui.theme.tracked

/** Detailed single-metric view with a larger scrubbable chart — MetricDetailView port. */
@Composable
fun MetricDetailSheet(detail: MetricDetail, onDismiss: () -> Unit) {
    var range by rememberSaveable { mutableStateOf(30) }

    AxSheet(onDismiss = onDismiss, title = detail.title) {
        Column(
            verticalArrangement = Arrangement.spacedBy(18.dp),
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 32.dp),
        ) {
            MetricHeader(detail)

            detail.sourceLabel?.let {
                Text(
                    "SOURCE · ${it.uppercase()}",
                    style = axMono(9, FontWeight.SemiBold).tracked(1.2),
                    color = Ax.Tertiary,
                )
            }

            if (detail.series.size > 1) {
                AxSegmented(
                    options = listOf(7 to "7d", 30 to "30d", 90 to "90d"),
                    selection = range,
                    onSelect = { range = it },
                    modifier = Modifier.fillMaxWidth(),
                )
                val n = minOf(range, detail.series.size)
                MetricLineChart(
                    values = detail.series.takeLast(n),
                    color = detail.color,
                    dates = detail.dates.takeLast(n),
                    formatValue = detail.format,
                    interactive = true,
                    height = 240.dp,
                )
                Text(
                    "Touch and drag the graph to read any day.",
                    style = axDisplay(11.5),
                    color = Ax.Tertiary,
                )
            }

            Box(Modifier.fillMaxWidth().height(1.dp).background(Ax.Border))

            Text(detail.description, style = axDisplay(13.5), color = Ax.Secondary)

            Box(Modifier.fillMaxWidth().height(1.dp).background(Ax.Border))

            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                for ((label, value) in detail.rows) {
                    Row(modifier = Modifier.fillMaxWidth()) {
                        Text(label, style = axDisplay(13), color = Ax.Secondary)
                        Spacer(Modifier.weight(1f))
                        Text(value, style = axMono(11, FontWeight.SemiBold), color = Ax.Primary)
                    }
                }
            }
        }
    }
}
