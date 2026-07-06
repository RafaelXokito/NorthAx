package app.northax.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.northax.domain.engine.SessionCompletion
import app.northax.domain.model.GarminActivity
import app.northax.ui.theme.Ax
import app.northax.ui.theme.axDisplay
import app.northax.ui.theme.axMono
import app.northax.ui.theme.tracked
import java.time.Duration
import java.time.Instant

// Shared "Instrument" building blocks — ports of the iOS Design/Components.swift.

// MARK: - Card

/**
 * Standard surface card: `Ax.Surface` fill + hairline stroke.
 * `highlighted` applies the today's-session treatment (orange border + wash).
 */
@Composable
fun AxCard(
    modifier: Modifier = Modifier,
    radius: Dp = 20.dp,
    padding: Dp = 18.dp,
    highlighted: Boolean = false,
    content: @Composable ColumnScope.() -> Unit,
) {
    val shape = RoundedCornerShape(radius)
    Column(
        modifier = modifier
            .clip(shape)
            .background(if (highlighted) Ax.AccentWash else Ax.Surface)
            .border(1.dp, if (highlighted) Ax.AccentBorder else Ax.Border, shape)
            .padding(padding),
        content = content,
    )
}

// MARK: - Section label

/** Mono uppercase section label above a card group. */
@Composable
fun SectionLabel(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text.uppercase(),
        style = axMono(10, FontWeight.SemiBold).tracked(1.8),
        color = Ax.Tertiary,
        modifier = modifier,
    )
}

// MARK: - Pill

enum class AxPillStyle { Tint, Outline }

/** Capsule badge: mono uppercase text, either on a 14%-tint fill or an outline. */
@Composable
fun AxPill(text: String, color: Color, style: AxPillStyle = AxPillStyle.Tint) {
    Text(
        text = text.uppercase(),
        style = axMono(10, FontWeight.SemiBold).tracked(0.8),
        color = color,
        modifier = Modifier
            .clip(CircleShape)
            .background(if (style == AxPillStyle.Tint) color.copy(alpha = 0.14f) else Color.Transparent)
            .border(1.dp, if (style == AxPillStyle.Outline) color.copy(alpha = 0.45f) else Color.Transparent, CircleShape)
            .padding(horizontal = 10.dp, vertical = 5.dp),
    )
}

/** Session completion badge: outline for planned (○ PLANNED), tint otherwise. */
@Composable
fun CompletionPill(completion: SessionCompletion) {
    val outline = completion == SessionCompletion.Planned
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        modifier = Modifier
            .clip(CircleShape)
            .background(if (outline) Color.Transparent else completion.color.copy(alpha = 0.14f))
            .border(1.dp, if (outline) completion.color.copy(alpha = 0.45f) else Color.Transparent, CircleShape)
            .padding(horizontal = 10.dp, vertical = 5.dp),
    ) {
        Icon(
            imageVector = completion.icon,
            contentDescription = null,
            tint = completion.color,
            modifier = Modifier.size(11.dp),
        )
        Text(
            text = completion.label.uppercase(),
            style = axMono(10, FontWeight.SemiBold).tracked(0.8),
            color = completion.color,
        )
    }
}

// MARK: - Icon tile

/** Icon on a 14%-opacity tint of its color. */
@Composable
fun IconTile(
    icon: ImageVector,
    color: Color,
    size: Dp = 38.dp,
    radius: Dp = 12.dp,
) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(size)
            .clip(RoundedCornerShape(radius))
            .background(color.copy(alpha = 0.14f)),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = color,
            modifier = Modifier.size(size * 0.5f),
        )
    }
}

// MARK: - Nav row

/**
 * Settings-style tappable row: icon tile + title/subtitle + trailing
 * value/chevron, in its own card.
 */
@Composable
fun NavRow(
    icon: ImageVector,
    iconColor: Color,
    title: String,
    subtitle: String? = null,
    subtitleColor: Color = Ax.Secondary,
    value: String? = null,
    showChevron: Boolean = true,
    isDestructive: Boolean = false,
    onClick: (() -> Unit)? = null,
) {
    val shape = RoundedCornerShape(16.dp)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Ax.Surface)
            .border(1.dp, Ax.Border, shape)
            .let { if (onClick != null) it.clickable(onClick = onClick) else it }
            .padding(16.dp),
    ) {
        IconTile(icon = icon, color = if (isDestructive) Ax.Red else iconColor)

        Column(verticalArrangement = Arrangement.spacedBy(3.dp), modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                style = axDisplay(15, FontWeight.SemiBold),
                color = if (isDestructive) Ax.Red else Ax.Primary,
            )
            if (subtitle != null) {
                Text(text = subtitle, style = axDisplay(12.5), color = subtitleColor)
            }
        }

        if (value != null) {
            Text(text = value, style = axMono(12), color = Ax.Secondary)
        }

        if (showChevron) {
            Icon(
                imageVector = Icons.Filled.ChevronRight,
                contentDescription = null,
                tint = Ax.Tertiary,
                modifier = Modifier.size(16.dp),
            )
        }
    }
}

// MARK: - Stat tile

/** Inset stat tile: mono label over a display value (TIME / EFFORT / LOAD). */
@Composable
fun StatTile(
    label: String,
    value: String,
    valueColor: Color = Ax.Primary,
    modifier: Modifier = Modifier,
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(5.dp),
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(Ax.Inset)
            .padding(vertical = 12.dp),
    ) {
        Text(
            text = label.uppercase(),
            style = axMono(9, FontWeight.SemiBold).tracked(1.2),
            color = Ax.Tertiary,
        )
        Text(text = value, style = axDisplay(17, FontWeight.Bold), color = valueColor)
    }
}

// MARK: - Contributor meter

/** Readiness contributor: mono label, thin colored progress bar, mono value. */
@Composable
fun ContributorMeter(label: String, value: String, score: Int, color: Color) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Text(
            text = label.uppercase(),
            style = axMono(10, FontWeight.SemiBold).tracked(1.2),
            color = Ax.Tertiary,
            modifier = Modifier.width(52.dp),
        )

        Box(
            modifier = Modifier
                .weight(1f)
                .height(6.dp)
                .clip(CircleShape)
                .background(Ax.Inset),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth(score.coerceIn(0, 100) / 100f)
                    .height(6.dp)
                    .clip(CircleShape)
                    .background(color),
            )
        }

        Text(
            text = value,
            style = axMono(11, FontWeight.SemiBold),
            color = Ax.Primary,
            modifier = Modifier.width(56.dp),
            textAlign = androidx.compose.ui.text.style.TextAlign.End,
        )
    }
}

// MARK: - Synced activity row

/** Activity list row shared by the intervals.icu and Strava screens. */
@Composable
fun SyncedActivityRow(activity: GarminActivity) {
    val shape = RoundedCornerShape(14.dp)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Ax.Surface)
            .border(1.dp, Ax.Border, shape)
            .padding(14.dp),
    ) {
        val route = activity.routePoints
        if (route != null && route.size > 1) {
            RouteThumbnail(points = route, color = activity.type.domain.color)
        } else {
            IconTile(icon = activity.type.domain.icon, color = activity.type.domain.color, size = 36.dp)
        }

        Column(verticalArrangement = Arrangement.spacedBy(3.dp), modifier = Modifier.weight(1f)) {
            Text(
                text = activity.name,
                style = axDisplay(14, FontWeight.SemiBold),
                color = Ax.Primary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            val meta = buildList {
                add(activity.formattedDuration)
                activity.formattedDistance?.let { add(it) }
                activity.avgHeartRate?.let { add("$it bpm") }
            }.joinToString(" · ").uppercase()
            Text(text = meta, style = axMono(10).tracked(0.4), color = Ax.Tertiary)
        }

        Text(
            text = AxFormat.relativeDate(activity.startTime),
            style = axMono(10),
            color = Ax.Tertiary,
        )
    }
}

// MARK: - Segmented control

/**
 * Inset-track segmented control: mono uppercase labels, lighter fill on the
 * active segment. Used for ranges (7D/30D/90D) and config choices (HR/Power…).
 */
@Composable
fun <T> AxSegmented(
    options: List<Pair<T, String>>,
    selection: T,
    onSelect: (T) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        modifier = modifier
            .clip(RoundedCornerShape(10.dp))
            .background(Ax.Inset)
            .padding(3.dp),
    ) {
        for ((value, label) in options) {
            val active = value == selection
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .weight(1f)
                    .height(30.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .background(if (active) Color.White.copy(alpha = 0.10f) else Color.Transparent)
                    .clickable { onSelect(value) },
            ) {
                Text(
                    text = label.uppercase(),
                    style = axMono(10, FontWeight.SemiBold).tracked(0.8),
                    color = if (active) Ax.Primary else Ax.Tertiary,
                )
            }
        }
    }
}

// MARK: - Empty state

/** Shared empty-state card: icon, title, message, optional CTA. */
@Composable
fun NoDataView(
    icon: ImageVector,
    title: String,
    message: String,
    ctaLabel: String? = null,
    onCta: (() -> Unit)? = null,
) {
    AxCard(modifier = Modifier.fillMaxWidth(), padding = 28.dp) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = Ax.Tertiary,
                modifier = Modifier.size(38.dp),
            )
            Text(text = title, style = axDisplay(17, FontWeight.Bold), color = Ax.Primary)
            Text(
                text = message,
                style = axDisplay(13),
                color = Ax.Secondary,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
            if (ctaLabel != null && onCta != null) {
                Spacer(Modifier.height(4.dp))
                AxButton(label = ctaLabel, onClick = onCta)
            }
        }
    }
}

// MARK: - Buttons

/** Primary filled accent button. */
@Composable
fun AxButton(
    label: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    color: Color = Ax.Accent,
    height: Dp = 50.dp,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(18.dp)
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .height(height)
            .clip(shape)
            .background(if (enabled) color else color.copy(alpha = 0.35f))
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 20.dp),
    ) {
        Text(text = label, style = axDisplay(15, FontWeight.Bold), color = Color.Black)
    }
}

/** Outline button (sync / disconnect actions). */
@Composable
fun AxOutlineButton(
    label: String,
    modifier: Modifier = Modifier,
    color: Color = Ax.Accent,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(12.dp)
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .height(44.dp)
            .clip(shape)
            .border(1.dp, color.copy(alpha = if (enabled) 0.5f else 0.2f), shape)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 16.dp),
    ) {
        Text(
            text = label,
            style = axDisplay(14, FontWeight.SemiBold),
            color = if (enabled) color else color.copy(alpha = 0.4f),
        )
    }
}

// MARK: - Formatters

object AxFormat {
    fun relativeDate(date: Instant): String {
        val days = Duration.between(date, Instant.now()).toDays()
        return when (days) {
            0L -> "Today"
            1L -> "Yesterday"
            else -> "${days}d ago"
        }
    }
}
