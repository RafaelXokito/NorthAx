package app.northax.ui.screens.metrics

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.northax.store.AthleteStore
import app.northax.ui.components.AxButton
import app.northax.ui.components.AxSheet
import app.northax.ui.theme.Ax
import app.northax.ui.theme.axDisplay
import app.northax.ui.theme.axMono
import kotlinx.coroutines.launch

/** Log wellness readings by hand — the ManualEntryView port. */
@Composable
fun ManualEntrySheet(store: AthleteStore, onDismiss: () -> Unit) {
    var hrv by rememberSaveable { mutableStateOf("") }
    var restingHr by rememberSaveable { mutableStateOf("") }
    var sleep by rememberSaveable { mutableStateOf("") }
    var weight by rememberSaveable { mutableStateOf("") }
    var saving by rememberSaveable { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    fun parse(text: String): Double? = text.replace(',', '.').toDoubleOrNull()
    val anyFilled = listOf(hrv, restingHr, sleep, weight).any { it.isNotBlank() }

    AxSheet(onDismiss = onDismiss, title = "Manual entry", doneLabel = "Cancel") {
        Column(
            verticalArrangement = Arrangement.spacedBy(14.dp),
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .imePadding()
                .padding(horizontal = 20.dp)
                .padding(bottom = 32.dp),
        ) {
            Text(
                "Log today's readings by hand. Anything you leave blank simply isn't provided by the manual source — your connected integrations still fill the rest.",
                style = axDisplay(13),
                color = Ax.Secondary,
            )

            ManualField("Heart Rate Variability", "ms", hrv) { hrv = it }
            ManualField("Resting Heart Rate", "bpm", restingHr) { restingHr = it }
            ManualField("Sleep", "hrs", sleep) { sleep = it }
            ManualField("Body Weight", "kg", weight) { weight = it }

            AxButton(
                label = if (saving) "Saving…" else "Save",
                enabled = anyFilled && !saving,
                modifier = Modifier.fillMaxWidth(),
                onClick = {
                    saving = true
                    scope.launch {
                        store.submitManualMetrics(
                            hrv = parse(hrv),
                            restingHR = parse(restingHr)?.toInt(),
                            sleepHours = parse(sleep),
                            weight = parse(weight),
                        )
                        saving = false
                        onDismiss()
                    }
                },
            )
        }
    }
}

@Composable
private fun ManualField(label: String, unit: String, value: String, onValueChange: (String) -> Unit) {
    val shape = RoundedCornerShape(16.dp)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Ax.Surface)
            .border(1.dp, Ax.Border, shape)
            .padding(horizontal = 16.dp, vertical = 6.dp),
    ) {
        Text(label, style = axDisplay(14, FontWeight.SemiBold), color = Ax.Primary)
        Spacer(Modifier.weight(1f))
        TextField(
            value = value,
            onValueChange = onValueChange,
            placeholder = { Text("–", style = axMono(13), color = Ax.Tertiary, textAlign = TextAlign.End) },
            singleLine = true,
            textStyle = axMono(13, FontWeight.SemiBold).copy(textAlign = TextAlign.End),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            colors = TextFieldDefaults.colors(
                focusedContainerColor = Color.Transparent,
                unfocusedContainerColor = Color.Transparent,
                focusedIndicatorColor = Color.Transparent,
                unfocusedIndicatorColor = Color.Transparent,
                cursorColor = Ax.Accent,
                focusedTextColor = Ax.Primary,
                unfocusedTextColor = Ax.Primary,
            ),
            modifier = Modifier.width(110.dp),
        )
        Text(unit.uppercase(), style = axMono(10), color = Ax.Tertiary)
    }
}
