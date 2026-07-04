package app.northax.ui.theme

import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp
import app.northax.R

// "Instrument" typography — Archivo for display/UI/numerals, JetBrains Mono for
// telemetry labels, stats, and chips (1:1 with the iOS Design/Typography.swift).

val ArchivoFamily = FontFamily(
    Font(R.font.archivo_regular, FontWeight.Normal),
    Font(R.font.archivo_medium, FontWeight.Medium),
    Font(R.font.archivo_semibold, FontWeight.SemiBold),
    Font(R.font.archivo_bold, FontWeight.Bold),
    Font(R.font.archivo_extrabold, FontWeight.ExtraBold),
    Font(R.font.archivo_black, FontWeight.Black),
)

val JetBrainsMonoFamily = FontFamily(
    Font(R.font.jetbrainsmono_regular, FontWeight.Normal),
    Font(R.font.jetbrainsmono_medium, FontWeight.Medium),
    Font(R.font.jetbrainsmono_semibold, FontWeight.SemiBold),
    Font(R.font.jetbrainsmono_bold, FontWeight.Bold),
)

/** Display text style: `axDisplay(size, weight)`. */
fun axDisplay(size: Int, weight: FontWeight = FontWeight.Normal): TextStyle = TextStyle(
    fontFamily = ArchivoFamily,
    fontWeight = weight,
    fontSize = size.sp,
)

fun axDisplay(size: Double, weight: FontWeight = FontWeight.Normal): TextStyle = TextStyle(
    fontFamily = ArchivoFamily,
    fontWeight = weight,
    fontSize = size.sp,
)

/** Mono text style: `axMono(size, weight)` — defaults to Medium like iOS. */
fun axMono(size: Int, weight: FontWeight = FontWeight.Medium): TextStyle = TextStyle(
    fontFamily = JetBrainsMonoFamily,
    fontWeight = weight,
    fontSize = size.sp,
)

/** Letter tracking helper: iOS `.tracking(pts)` at a given font size ≈ pts sp. */
fun TextStyle.tracked(letterSpacing: Double): TextStyle =
    copy(letterSpacing = letterSpacing.sp)

fun TextStyle.tracked(letterSpacing: TextUnit): TextStyle =
    copy(letterSpacing = letterSpacing)
