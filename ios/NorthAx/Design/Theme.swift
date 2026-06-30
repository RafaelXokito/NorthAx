import SwiftUI

// Using `where Self == Color` so dot-shorthand works in foregroundStyle / background.
extension ShapeStyle where Self == Color {
    static var axBackground: Color { Color(red: 0.05, green: 0.05, blue: 0.09) }
    static var axSurface:    Color { Color(white: 0.12) }
    static var axBorder:     Color { Color(white: 1, opacity: 0.08) }
    static var axAccent:     Color { Color(red: 1.0,  green: 0.55, blue: 0.15) }
    static var axGreen:      Color { Color(red: 0.18, green: 0.88, blue: 0.48) }
    static var axRed:        Color { Color(red: 1.0,  green: 0.30, blue: 0.30) }
    static var axBlue:       Color { Color(red: 0.35, green: 0.62, blue: 1.0)  }
    static var axPurple:     Color { Color(red: 0.70, green: 0.42, blue: 1.0)  }
    static var axPrimary:    Color { .white }
    static var axSecondary:  Color { Color(white: 1, opacity: 0.55) }
    static var axTertiary:   Color { Color(white: 1, opacity: 0.30) }
}
