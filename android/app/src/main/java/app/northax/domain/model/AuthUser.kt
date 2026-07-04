package app.northax.domain.model

import kotlinx.serialization.Serializable

@Serializable
data class AuthUser(
    val id: String,
    val name: String,
    val email: String? = null,
)
