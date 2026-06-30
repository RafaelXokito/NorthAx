import Foundation

// Auth DTOs mirroring the OpenAPI schemas (§6.1). Property names match the
// camelCase wire keys 1:1, so no CodingKeys are needed.

struct EmailSignInRequest: Encodable {
    var email: String
    var password: String
}

struct EmailSignUpRequest: Encodable {
    var name: String
    var email: String
    var password: String
}

struct UserSummaryDTO: Decodable {
    var id: String
    var name: String
    var email: String?
}

struct AuthResponse: Decodable {
    var accessToken: String
    var refreshToken: String
    var user: UserSummaryDTO
}

struct RefreshRequest: Encodable {
    var refreshToken: String
}

struct RefreshResponse: Decodable {
    var accessToken: String
    var refreshToken: String
}

struct UserProfileDTO: Decodable {
    var id: String
    var name: String
    var email: String?
    var createdAt: Date
}

struct UpdateProfileRequest: Encodable {
    var name: String
}
