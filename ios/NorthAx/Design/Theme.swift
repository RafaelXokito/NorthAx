import SwiftUI

// "Instrument" design tokens.
// Using `where Self == Color` so dot-shorthand works in foregroundStyle / background.
extension ShapeStyle where Self == Color {
    // Surfaces
    static var axBackground: Color { Color(hex: 0x0B0C0E) }
    static var axSurface:    Color { Color(hex: 0x141517) }
    static var axBorder:     Color { Color(white: 1, opacity: 0.065) }
    static var axInset:      Color { Color(white: 1, opacity: 0.05) }

    // Signal
    static var axAccent:     Color { Color(hex: 0xFF6A1A) }
    static var axGreen:      Color { Color(hex: 0x35E08A) }
    static var axAmber:      Color { Color(hex: 0xF5A623) }
    static var axRed:        Color { Color(hex: 0xFF4D4D) }
    static var axBlue:       Color { Color(hex: 0x4EA8FF) }
    static var axPurple:     Color { Color(hex: 0x9B8CFF) }

    // Sport hues
    static var axCycling:       Color { Color(hex: 0xFF8A3C) }
    static var axStrengthSport: Color { Color(hex: 0xFF5C4D) }
    static var axRecovery:      Color { Color(hex: 0x35E0C8) }

    // Text
    static var axPrimary:    Color { Color(hex: 0xF5F5F3) }
    static var axSecondary:  Color { Color(hex: 0xF5F5F3, opacity: 0.5) }
    static var axTertiary:   Color { Color(hex: 0xF5F5F3, opacity: 0.4) }

    // Highlight pair (today's-session card treatment)
    static var axAccentBorder: Color { Color(hex: 0xFF6A1A, opacity: 0.4) }
    static var axAccentWash:   Color { Color(hex: 0xFF6A1A, opacity: 0.05) }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            red:     Double((hex >> 16) & 0xFF) / 255,
            green:   Double((hex >> 8)  & 0xFF) / 255,
            blue:    Double(hex         & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension DailyReadiness.Status {
    /// Zone color for the readiness gauge, pills, and status text.
    var color: Color {
        switch self {
        case .peak:     return .axAccent
        case .high:     return .axGreen
        case .moderate: return .axAmber
        case .low:      return .axRed
        case .rest:     return .axTertiary
        }
    }
}
