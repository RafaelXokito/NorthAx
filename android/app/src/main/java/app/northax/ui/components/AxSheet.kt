package app.northax.ui.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.foundation.clickable
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.northax.ui.theme.Ax
import app.northax.ui.theme.axDisplay
import app.northax.ui.theme.axMono
import app.northax.ui.theme.tracked

/**
 * Full-height dark modal sheet with an optional title row and Done action —
 * the Android stand-in for the iOS `NavigationStack`-in-a-sheet pattern.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AxSheet(
    onDismiss: () -> Unit,
    title: String? = null,
    doneLabel: String = "Done",
    content: @Composable ColumnScope.() -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Ax.Background,
        dragHandle = null,
    ) {
        Column {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 14.dp),
            ) {
                if (title != null) {
                    Text(
                        text = title.uppercase(),
                        style = axMono(11, FontWeight.SemiBold).tracked(1.6),
                        color = Ax.Tertiary,
                    )
                }
                Spacer(Modifier.weight(1f))
                Text(
                    text = doneLabel,
                    style = axDisplay(15, FontWeight.SemiBold),
                    color = Ax.Accent,
                    modifier = Modifier.clickable(onClick = onDismiss).padding(4.dp),
                )
            }
            content()
        }
    }
}
