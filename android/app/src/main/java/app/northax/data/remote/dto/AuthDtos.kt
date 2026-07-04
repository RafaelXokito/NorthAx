package app.northax.data.remote.dto

import app.northax.data.remote.ApiInstant
import kotlinx.serialization.Serializable

// Auth DTOs mirroring the OpenAPI schemas. Property names match the camelCase
// wire keys 1:1.

@Serializable
data class EmailSignInRequest(val email: String, val password: String)

@Serializable
data class EmailSignUpRequest(val name: String, val email: String, val password: String)

@Serializable
data class UserSummaryDto(val id: String, val name: String, val email: String? = null)

@Serializable
data class AuthResponse(
    val accessToken: String,
    val refreshToken: String,
    val user: UserSummaryDto,
)

@Serializable
data class RefreshRequest(val refreshToken: String)

@Serializable
data class RefreshResponse(val accessToken: String, val refreshToken: String)

@Serializable
data class UserProfileDto(
    val id: String,
    val name: String,
    val email: String? = null,
    val createdAt: ApiInstant,
)

@Serializable
data class UpdateProfileRequest(val name: String)
