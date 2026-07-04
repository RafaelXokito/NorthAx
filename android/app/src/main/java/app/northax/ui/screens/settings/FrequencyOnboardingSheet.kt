package app.northax.ui.screens.settings

import androidx.compose.animation.AnimatedContent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.CompareArrows
import androidx.compose.material.icons.automirrored.filled.DirectionsRun
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.MonitorHeart
import androidx.compose.material.icons.filled.Psychology
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.northax.domain.model.TrainingDomain
import app.northax.domain.model.TrainingFrequency
import app.northax.store.AthleteStore
import app.northax.ui.components.AxSheet
import app.northax.ui.theme.Ax
import app.northax.ui.theme.axDisplay
import app.northax.ui.theme.axMono
import app.northax.ui.theme.tracked
import kotlinx.coroutines.launch

/** First-launch sheet that collects training frequency — FrequencyOnboardingView port. */
@Composable
fun FrequencyOnboardingSheet(store: AthleteStore, onDismiss: () -> Unit) {
    var step by remember { mutableStateOf(0) } // 0 = welcome, 1 = frequency
    var localFrequency by remember { mutableStateOf(TrainingFrequency.defaultFrequency) }
    val scope = rememberCoroutineScope()

    val domains = listOf(
        TrainingDomain.Cycling, TrainingDomain.Running, TrainingDomain.Strength,
        TrainingDomain.Swimming, TrainingDomain.Triathlon, TrainingDomain.Mobility,
    )

    AxSheet(onDismiss = onDismiss, doneLabel = "Later") {
        AnimatedContent(targetState = step, label = "onboarding") { s ->
            if (s == 0) {
                // Welcome step
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(28.dp),
                    modifier = Modifier
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = 24.dp)
                        .padding(top = 24.dp, bottom = 40.dp),
                ) {
                    Icon(
                        Icons.AutoMirrored.Filled.DirectionsRun,
                        contentDescription = null,
                        tint = Ax.Accent,
                        modifier = Modifier.size(64.dp),
                    )
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("NorthAx", style = axDisplay(36, FontWeight.ExtraBold).tracked(-1.08), color = Ax.Primary)
                        Text(
                            "YOUR INTELLIGENT TRAINING\nOPERATING SYSTEM",
                            style = axMono(11, FontWeight.SemiBold).tracked(1.8),
                            color = Ax.Secondary,
                            textAlign = TextAlign.Center,
                        )
                    }

                    Column(verticalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
                        OnboardingFeatureRow(Icons.Filled.MonitorHeart, "Reads your HRV, sleep, and load every morning")
                        OnboardingFeatureRow(Icons.Filled.Psychology, "Explains every recommendation in plain language")
                        OnboardingFeatureRow(Icons.Filled.CalendarMonth, "Builds and adjusts your training plan automatically")
                        OnboardingFeatureRow(Icons.AutoMirrored.Filled.CompareArrows, "Adapts when you need to swap activities")
                    }

                    OnboardingCta(label = "Let's build your plan", color = Ax.Accent) { step = 1 }
                }
            } else {
                // Frequency step
                Column {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(20.dp),
                        modifier = Modifier
                            .weight(1f, fill = false)
                            .verticalScroll(rememberScrollState())
                            .padding(horizontal = 24.dp)
                            .padding(top = 16.dp, bottom = 16.dp),
                    ) {
                        Text(
                            "How do you want to train?",
                            style = axDisplay(22, FontWeight.ExtraBold).tracked(-0.44),
                            color = Ax.Primary,
                            textAlign = TextAlign.Center,
                        )
                        Text(
                            "Set your weekly sessions per sport. You can always change this in Settings.",
                            style = axDisplay(13.5),
                            color = Ax.Secondary,
                            textAlign = TextAlign.Center,
                        )

                        // Per-sport weekday toggles
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(16.dp))
                                .background(Ax.Surface)
                                .border(1.dp, Ax.Border, RoundedCornerShape(16.dp)),
                        ) {
                            domains.forEachIndexed { i, domain ->
                                if (i > 0) {
                                    Box(
                                        Modifier
                                            .fillMaxWidth()
                                            .padding(horizontal = 16.dp)
                                            .height(1.dp)
                                            .background(Ax.Border)
                                    )
                                }
                                OnboardingDomainRow(
                                    domain = domain,
                                    days = localFrequency.weekdays(domain),
                                    onToggle = { wd -> localFrequency = localFrequency.toggling(wd, domain) },
                                )
                            }
                        }

                        val n = localFrequency.totalTrainingDays
                        val r = localFrequency.restDaysPerWeek
                        Text(
                            "$n TRAINING ${if (n == 1) "DAY" else "DAYS"} · $r REST ${if (r == 1) "DAY" else "DAYS"} PER WEEK",
                            style = axMono(10, FontWeight.SemiBold).tracked(0.8),
                            color = Ax.Secondary,
                        )
                    }

                    // Sticky CTA
                    Column(modifier = Modifier.padding(horizontal = 24.dp, vertical = 20.dp)) {
                        val empty = localFrequency.totalTrainingDays == 0
                        OnboardingCta(
                            label = if (empty) "Skip for now" else "Build My Plan →",
                            color = if (empty) Ax.Secondary else Ax.Accent,
                        ) {
                            store.updateTrainingFrequency(localFrequency)
                            store.setHasSetFrequencyFlag(true)
                            onDismiss()
                            if (localFrequency.totalTrainingDays > 0) {
                                scope.launch { store.applyPlanChanges() }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun OnboardingFeatureRow(icon: ImageVector, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Icon(icon, contentDescription = null, tint = Ax.Accent, modifier = Modifier.size(22.dp))
        Text(text, style = axDisplay(13.5), color = Ax.Secondary)
    }
}

@Composable
private fun OnboardingCta(label: String, color: Color, onClick: () -> Unit) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .fillMaxWidth()
            .height(54.dp)
            .clip(RoundedCornerShape(18.dp))
            .background(color)
            .clickable(onClick = onClick),
    ) {
        Text(label, style = axDisplay(15, FontWeight.Bold), color = Ax.Background)
    }
}

private val weekdayLabels = listOf("M", "T", "W", "T", "F", "S", "S")

@Composable
private fun OnboardingDomainRow(domain: TrainingDomain, days: Set<Int>, onToggle: (Int) -> Unit) {
    Column(
        verticalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .size(32.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .background((if (days.isEmpty()) Color.White else domain.color).copy(alpha = 0.08f)),
            ) {
                Icon(
                    domain.icon,
                    contentDescription = null,
                    tint = if (days.isEmpty()) Ax.Tertiary else domain.color,
                    modifier = Modifier.size(17.dp),
                )
            }
            Text(
                domain.raw,
                style = axDisplay(14, FontWeight.SemiBold),
                color = if (days.isEmpty()) Ax.Secondary else Ax.Primary,
            )
        }

        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth()) {
            for (wd in 0..6) {
                val on = wd in days
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier
                        .weight(1f)
                        .height(38.dp)
                        .clip(RoundedCornerShape(10.dp))
                        .background(if (on) domain.color else Ax.Inset)
                        .clickable { onToggle(wd) },
                ) {
                    Text(
                        weekdayLabels[wd],
                        style = axMono(12, FontWeight.SemiBold),
                        color = if (on) Ax.Background else Ax.Tertiary,
                    )
                }
            }
        }
    }
}
