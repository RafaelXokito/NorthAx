package app.northax.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// "Instrument" design tokens — 1:1 with the iOS Design/Theme.swift.
object Ax {
    // Surfaces
    val Background = Color(0xFF0B0C0E)
    val Surface = Color(0xFF141517)
    val Border = Color.White.copy(alpha = 0.065f)
    val Inset = Color.White.copy(alpha = 0.05f)

    // Signal
    val Accent = Color(0xFFFF6A1A)
    val Green = Color(0xFF35E08A)
    val Amber = Color(0xFFF5A623)
    val Red = Color(0xFFFF4D4D)
    val Blue = Color(0xFF4EA8FF)
    val Purple = Color(0xFF9B8CFF)

    // Sport hues
    val Cycling = Color(0xFFFF8A3C)
    val StrengthSport = Color(0xFFFF5C4D)
    val Recovery = Color(0xFF35E0C8)

    // Text
    val Primary = Color(0xFFF5F5F3)
    val Secondary = Primary.copy(alpha = 0.5f)
    val Tertiary = Primary.copy(alpha = 0.4f)

    // Highlight pair (today's-session card treatment)
    val AccentBorder = Accent.copy(alpha = 0.4f)
    val AccentWash = Accent.copy(alpha = 0.05f)

    /// Shared training-zone ramp (Z1–Z5), used by the workout effort graph and
    /// the activity stream zone bands.
    fun zone(z: Int): Color = when (z) {
        1 -> Blue
        2 -> Green
        3 -> Amber
        4 -> Cycling
        5 -> Red
        else -> Tertiary
    }
}

private val NorthAxColorScheme = darkColorScheme(
    primary = Ax.Accent,
    onPrimary = Color.Black,
    background = Ax.Background,
    onBackground = Ax.Primary,
    surface = Ax.Surface,
    onSurface = Ax.Primary,
    surfaceVariant = Ax.Surface,
    onSurfaceVariant = Ax.Secondary,
    outline = Ax.Border,
    error = Ax.Red,
)

@Composable
fun NorthAxTheme(content: @Composable () -> Unit) {
    // The app is dark-only, like iOS (`.preferredColorScheme(.dark)`).
    MaterialTheme(
        colorScheme = NorthAxColorScheme,
        content = content,
    )
}
