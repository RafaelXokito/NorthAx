package app.northax.ui.screens.auth

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Insights
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.MailOutline
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Psychology
import androidx.compose.material.icons.filled.SyncAlt
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.northax.BuildConfig
import app.northax.store.AuthService
import app.northax.ui.theme.Ax
import app.northax.ui.theme.axDisplay
import app.northax.ui.theme.axMono
import app.northax.ui.theme.tracked

/** Sign in and account creation flow — the SignInView port. */
@Composable
fun SignInScreen(auth: AuthService) {
    var isRegistering by rememberSaveable { mutableStateOf(false) }
    var name by rememberSaveable { mutableStateOf("") }
    var email by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }

    Box(modifier = Modifier.fillMaxSize().background(Ax.Background)) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .imePadding()
                .padding(horizontal = 24.dp)
                .widthIn(max = 480.dp),
        ) {
            Spacer(Modifier.height(52.dp))

            // Branding
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .size(88.dp)
                    .background(Ax.Accent.copy(alpha = 0.15f), CircleShape),
            ) {
                Icon(
                    imageVector = Icons.Filled.Bolt,
                    contentDescription = null,
                    tint = Ax.Accent,
                    modifier = Modifier.size(44.dp),
                )
            }
            Spacer(Modifier.height(18.dp))
            Text("NorthAx", style = axDisplay(40, FontWeight.ExtraBold).tracked(-1.2), color = Ax.Primary)
            Spacer(Modifier.height(6.dp))
            Text(
                "YOUR INTELLIGENT TRAINING OS",
                style = axMono(11, FontWeight.SemiBold).tracked(1.8),
                color = Ax.Secondary,
            )

            Spacer(Modifier.height(36.dp))

            // Features
            Column(
                verticalArrangement = Arrangement.spacedBy(18.dp),
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(20.dp))
                    .background(Ax.Surface)
                    .border(1.dp, Ax.Border, RoundedCornerShape(20.dp))
                    .padding(24.dp),
            ) {
                FeatureRow(Icons.Filled.FavoriteBorder, "Daily readiness", "HRV, sleep, and load in one score")
                FeatureRow(Icons.Filled.Insights, "Adaptive plan", "Two weeks ahead, tuned to your recovery")
                FeatureRow(Icons.Filled.SyncAlt, "Garmin & Strava", "Workouts sync in through intervals.icu")
                FeatureRow(Icons.Filled.Psychology, "AI coach", "Ask anything about your training")
            }

            Spacer(Modifier.height(24.dp))

            // Form
            Column(
                verticalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.fillMaxWidth().animateContentSize(),
            ) {
                if (isRegistering) {
                    AuthField(
                        value = name, onValueChange = { name = it },
                        placeholder = "Name", icon = Icons.Filled.Person,
                        keyboardType = KeyboardType.Text,
                    )
                }
                AuthField(
                    value = email, onValueChange = { email = it },
                    placeholder = "Email", icon = Icons.Filled.MailOutline,
                    keyboardType = KeyboardType.Email,
                )
                AuthField(
                    value = password, onValueChange = { password = it },
                    placeholder = "Password", icon = Icons.Filled.Lock,
                    keyboardType = KeyboardType.Password,
                    visualTransformation = PasswordVisualTransformation(),
                )

                // Submit
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(54.dp)
                        .clip(RoundedCornerShape(18.dp))
                        .background(Ax.Accent)
                        .clickable(enabled = !auth.isAuthenticating) {
                            if (isRegistering) auth.register(name, email, password)
                            else auth.signIn(email, password)
                        },
                ) {
                    if (auth.isAuthenticating) {
                        CircularProgressIndicator(color = Color.Black, modifier = Modifier.size(22.dp))
                    } else {
                        Text(
                            text = if (isRegistering) "Create account" else "Sign in",
                            style = axDisplay(16, FontWeight.Bold),
                            color = Color.Black,
                        )
                    }
                }

                auth.authError?.let { error ->
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(Ax.Red.copy(alpha = 0.08f))
                            .padding(12.dp),
                    ) {
                        Icon(Icons.Filled.ErrorOutline, contentDescription = null, tint = Ax.Red, modifier = Modifier.size(18.dp))
                        Text(error, style = axDisplay(13), color = Ax.Red)
                    }
                }

                Text(
                    text = if (isRegistering) "Already have an account? Sign in"
                    else "Don't have an account? Create one",
                    style = axDisplay(13.5, FontWeight.Medium),
                    color = Ax.Secondary,
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable {
                            isRegistering = !isRegistering
                            auth.authError = null
                        }
                        .padding(vertical = 10.dp),
                )

                if (BuildConfig.DEBUG) {
                    Text(
                        text = "Continue as Debug User",
                        style = axMono(11, FontWeight.SemiBold).tracked(0.8),
                        color = Ax.Tertiary,
                        textAlign = TextAlign.Center,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { auth.signInAsDebugUser() }
                            .padding(vertical = 6.dp),
                    )
                }
            }

            Spacer(Modifier.height(32.dp))
        }
    }
}

@Composable
private fun FeatureRow(icon: ImageVector, title: String, subtitle: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Icon(imageVector = icon, contentDescription = null, tint = Ax.Accent, modifier = Modifier.size(22.dp))
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = axDisplay(14.5, FontWeight.SemiBold), color = Ax.Primary)
            Text(subtitle, style = axDisplay(12.5), color = Ax.Secondary)
        }
    }
}

@Composable
private fun AuthField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    icon: ImageVector,
    keyboardType: KeyboardType,
    visualTransformation: VisualTransformation = VisualTransformation.None,
) {
    val shape = RoundedCornerShape(14.dp)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Ax.Surface)
            .border(1.dp, Ax.Border, shape),
    ) {
        Spacer(Modifier.width(16.dp))
        Icon(imageVector = icon, contentDescription = null, tint = Ax.Secondary, modifier = Modifier.size(20.dp))
        TextField(
            value = value,
            onValueChange = onValueChange,
            placeholder = { Text(placeholder, style = axDisplay(15), color = Ax.Tertiary) },
            singleLine = true,
            textStyle = axDisplay(15),
            visualTransformation = visualTransformation,
            keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
            colors = TextFieldDefaults.colors(
                focusedContainerColor = Color.Transparent,
                unfocusedContainerColor = Color.Transparent,
                focusedIndicatorColor = Color.Transparent,
                unfocusedIndicatorColor = Color.Transparent,
                cursorColor = Ax.Accent,
                focusedTextColor = Color.White,
                unfocusedTextColor = Color.White,
            ),
            modifier = Modifier.weight(1f),
        )
    }
}
