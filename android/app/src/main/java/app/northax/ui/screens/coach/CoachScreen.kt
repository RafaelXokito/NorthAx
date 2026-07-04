package app.northax.ui.screens.coach

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Psychology
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import androidx.compose.ui.unit.dp
import app.northax.domain.model.CoachMessage
import app.northax.store.AthleteStore
import app.northax.ui.theme.Ax
import app.northax.ui.theme.axDisplay
import app.northax.ui.theme.axMono
import app.northax.ui.theme.tracked
import kotlinx.coroutines.launch
import java.time.Instant

/**
 * AI coach chat with quick questions and streamed replies — the CoachView
 * port. (Not shown in the tab bar, matching iOS; kept for later.)
 */
@Composable
fun CoachScreen(store: AthleteStore) {
    var input by rememberSaveable { mutableStateOf("") }
    var isTyping by rememberSaveable { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()

    fun send(text: String) {
        val trimmed = text.trim()
        if (trimmed.isEmpty() || isTyping) return
        input = ""
        store.messages = store.messages + CoachMessage(content = trimmed, isCoach = false, timestamp = Instant.now())
        isTyping = true
        scope.launch {
            store.respond(trimmed)
            isTyping = false
        }
    }

    LaunchedEffect(store.messages.size, isTyping) {
        if (store.messages.isNotEmpty()) {
            listState.animateScrollToItem(store.messages.size - 1)
        }
    }

    Column(modifier = Modifier.fillMaxSize().background(Ax.Background).imePadding()) {
        LazyColumn(
            state = listState,
            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier.weight(1f),
        ) {
            items(count = store.messages.size, key = { store.messages[it].id }) { i ->
                ChatBubble(store.messages[i])
            }
            if (isTyping && store.messages.lastOrNull()?.content?.isEmpty() != false) {
                item(key = "typing") {
                    Text("…", style = axDisplay(18), color = Ax.Tertiary, modifier = Modifier.padding(start = 44.dp))
                }
            }
        }

        Box(Modifier.fillMaxWidth().height(1.dp).background(Ax.Border))

        // Quick questions
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier
                .horizontalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 10.dp),
        ) {
            for (question in CoachMessage.quickQuestions) {
                Text(
                    text = question,
                    style = axDisplay(12.5, FontWeight.Medium),
                    color = Ax.Secondary,
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(Ax.Surface)
                        .border(1.dp, Ax.Border, CircleShape)
                        .clickable { send(question) }
                        .padding(horizontal = 14.dp, vertical = 8.dp),
                )
            }
        }

        // Input bar
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(bottom = 12.dp),
        ) {
            TextField(
                value = input,
                onValueChange = { input = it },
                placeholder = { Text("Ask your coach…", style = axDisplay(14), color = Ax.Tertiary) },
                singleLine = true,
                textStyle = axDisplay(14),
                shape = CircleShape,
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = Ax.Surface,
                    unfocusedContainerColor = Ax.Surface,
                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent,
                    cursorColor = Ax.Accent,
                    focusedTextColor = Ax.Primary,
                    unfocusedTextColor = Ax.Primary,
                ),
                modifier = Modifier.weight(1f),
            )
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .size(44.dp)
                    .clip(CircleShape)
                    .background(if (input.isBlank()) Ax.Surface else Ax.Accent)
                    .clickable { send(input) },
            ) {
                Icon(
                    imageVector = Icons.Filled.ArrowUpward,
                    contentDescription = "Send",
                    tint = if (input.isBlank()) Ax.Tertiary else Color.Black,
                    modifier = Modifier.size(20.dp),
                )
            }
        }
    }
}

@Composable
private fun ChatBubble(message: CoachMessage) {
    Row(modifier = Modifier.fillMaxWidth()) {
        if (message.isCoach) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .size(30.dp)
                    .clip(CircleShape)
                    .background(Ax.Accent.copy(alpha = 0.14f)),
            ) {
                Icon(Icons.Filled.Psychology, contentDescription = null, tint = Ax.Accent, modifier = Modifier.size(16.dp))
            }
            Spacer(Modifier.size(8.dp))
        } else {
            Spacer(Modifier.weight(1f))
        }

        val shape = RoundedCornerShape(18.dp)
        Text(
            text = message.content.ifEmpty { "…" },
            style = axDisplay(14),
            color = if (message.isCoach) Ax.Primary else Color.Black,
            modifier = Modifier
                .widthIn(max = 300.dp)
                .clip(shape)
                .background(if (message.isCoach) Ax.Surface else Ax.Accent)
                .border(1.dp, if (message.isCoach) Ax.Border else Color.Transparent, shape)
                .padding(horizontal = 14.dp, vertical = 10.dp),
        )
    }
}
