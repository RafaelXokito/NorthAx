package app.northax.store

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.northax.data.AppContainer
import app.northax.data.remote.ApiError
import app.northax.data.remote.dto.AuthResponse
import app.northax.data.remote.dto.EmailSignInRequest
import app.northax.data.remote.dto.EmailSignUpRequest
import app.northax.data.remote.dto.UserProfileDto
import app.northax.domain.model.AuthUser
import kotlinx.coroutines.launch

/**
 * Owns the authenticated session. Email/password credentials are exchanged
 * with the backend for an access + refresh JWT pair stored encrypted. The
 * session is restored on launch from those tokens, and dropped if the backend
 * revokes them — a 1:1 port of the iOS AuthService.
 */
class AuthService(private val container: AppContainer) : ViewModel() {

    var currentUser by mutableStateOf<AuthUser?>(null)
        private set
    var authError by mutableStateOf<String?>(null)
    var isAuthenticating by mutableStateOf(false)
        private set

    private val client = container.apiClient
    private val tokens = container.tokens
    private val prefs = container.prefs

    val isAuthenticated: Boolean get() = currentUser != null

    init {
        observeSessionExpiry()
        restoreSession()
    }

    // MARK: - Email / Password

    /** Sign in with an existing account. */
    fun signIn(email: String, password: String) {
        val trimmed = email.trim()
        if (!isValidEmail(trimmed)) {
            authError = "Enter a valid email address."
            return
        }
        if (password.isEmpty()) {
            authError = "Enter your password."
            return
        }
        authError = null
        viewModelScope.launch { exchange("auth/login") { post(it, EmailSignInRequest(trimmed, password)) } }
    }

    /** Create a new account, then start an authenticated session. */
    fun register(name: String, email: String, password: String) {
        val trimmedName = name.trim()
        val trimmedEmail = email.trim()
        if (trimmedName.isEmpty()) {
            authError = "Enter your name."
            return
        }
        if (!isValidEmail(trimmedEmail)) {
            authError = "Enter a valid email address."
            return
        }
        if (password.length < 8) {
            authError = "Password must be at least 8 characters."
            return
        }
        authError = null
        viewModelScope.launch {
            exchange("auth/register") { post(it, EmailSignUpRequest(trimmedName, trimmedEmail, password)) }
        }
    }

    private suspend fun post(path: String, body: EmailSignInRequest): AuthResponse =
        client.post(path, body, authenticated = false)

    private suspend fun post(path: String, body: EmailSignUpRequest): AuthResponse =
        client.post(path, body, authenticated = false)

    /** Exchange credentials for app tokens and open the session. */
    private suspend fun exchange(path: String, request: suspend (String) -> AuthResponse) {
        isAuthenticating = true
        try {
            val resp = request(path)
            tokens.save(resp.accessToken, resp.refreshToken)
            setUser(AuthUser(resp.user.id, resp.user.name, resp.user.email))
        } catch (e: ApiError) {
            authError = e.userMessage
        } catch (_: Exception) {
            authError = "Sign in failed. Please try again."
        } finally {
            isAuthenticating = false
        }
    }

    // MARK: - Sign Out

    fun signOut() {
        // Best-effort server revoke; local clear is authoritative.
        viewModelScope.launch {
            try {
                client.send("DELETE", "auth/session")
            } catch (_: Exception) {
            }
        }
        tokens.clear()
        prefs.cachedUser = null
        currentUser = null
    }

    // MARK: - Session restore

    private fun restoreSession() {
        if (!tokens.hasSession) return
        // Optimistic restore from cache, then validate against the backend.
        prefs.cachedUser?.let { currentUser = it }
        viewModelScope.launch {
            try {
                val profile: UserProfileDto = client.get("user/profile")
                setUser(AuthUser(profile.id, profile.name, profile.email))
            } catch (e: ApiError) {
                if (e.isUnauthorized) signOut()
                // Other errors: keep optimistic session; will retry next launch.
            } catch (_: Exception) {
            }
        }
    }

    private fun setUser(user: AuthUser) {
        currentUser = user
        prefs.cachedUser = user
    }

    // MARK: - Debug bypass

    /** Local-only session for offline UI work (debug builds only). Has no
     *  backend tokens, so live API calls will not succeed — the app falls back
     *  to the client engines. */
    fun signInAsDebugUser(name: String = "Rafael") {
        setUser(AuthUser("debug-${java.util.UUID.randomUUID()}", name, null))
        authError = null
    }

    private fun observeSessionExpiry() {
        viewModelScope.launch {
            client.sessionExpired.collect {
                currentUser = null
                prefs.cachedUser = null
            }
        }
    }

    private companion object {
        // Pragmatic check: one @, non-empty local part, dotted domain.
        val emailRegex = Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")
        fun isValidEmail(email: String): Boolean = emailRegex.matches(email)
    }
}
