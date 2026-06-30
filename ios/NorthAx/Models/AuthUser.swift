import Foundation

struct AuthUser: Codable, Equatable {
    var id: String
    var name: String
    var email: String?
}
