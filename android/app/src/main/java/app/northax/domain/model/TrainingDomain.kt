package app.northax.domain.model

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsBike
import androidx.compose.material.icons.automirrored.filled.DirectionsRun
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.Pool
import androidx.compose.material.icons.filled.SelfImprovement
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import app.northax.ui.theme.Ax

/** Raw values match the backend wire strings ("Cycling", "Running", …). */
enum class TrainingDomain(val raw: String) {
    Cycling("Cycling"),
    Running("Running"),
    Strength("Strength"),
    Swimming("Swimming"),
    Triathlon("Triathlon"),
    Mobility("Mobility"),
    Recovery("Recovery");

    val icon: ImageVector
        get() = when (this) {
            Cycling -> Icons.AutoMirrored.Filled.DirectionsBike
            Running -> Icons.AutoMirrored.Filled.DirectionsRun
            Strength -> Icons.Filled.FitnessCenter
            Swimming -> Icons.Filled.Pool
            Triathlon -> Icons.Filled.EmojiEvents
            Mobility -> Icons.Filled.SelfImprovement
            Recovery -> Icons.Filled.Favorite
        }

    val color: Color
        get() = when (this) {
            Cycling -> Ax.Cycling
            Running -> Ax.Green
            Strength -> Ax.StrengthSport
            Swimming -> Ax.Blue
            Triathlon -> Ax.Purple
            Mobility -> Ax.Amber
            Recovery -> Ax.Recovery
        }

    companion object {
        fun fromRaw(raw: String): TrainingDomain? = entries.firstOrNull { it.raw == raw }
    }
}
