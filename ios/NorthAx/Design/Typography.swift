import SwiftUI

// "Instrument" typography: Archivo for display/UI/numerals, JetBrains Mono for
// telemetry labels, stats, and chips. Weight → face is mapped explicitly because
// `Font.custom` ignores `.weight()` on non-variable fonts.
extension Font {
    static func axDisplay(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let face: String
        switch weight {
        case .medium:            face = "Archivo-Medium"
        case .semibold:          face = "Archivo-SemiBold"
        case .bold:              face = "Archivo-Bold"
        case .heavy:             face = "Archivo-ExtraBold"
        case .black:             face = "Archivo-Black"
        default:                 face = "Archivo-Regular"
        }
        return .custom(face, fixedSize: size)
    }

    static func axMono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        let face: String
        switch weight {
        case .semibold:          face = "JetBrainsMono-SemiBold"
        case .bold:              face = "JetBrainsMono-Bold"
        case .regular:           face = "JetBrainsMono-Regular"
        default:                 face = "JetBrainsMono-Medium"
        }
        return .custom(face, fixedSize: size)
    }
}

extension View {
    /// Mono uppercase section label: `TODAY'S SESSION`, `ENROLLED SPORTS`, …
    func axSectionLabel() -> some View {
        self
            .font(.axMono(10, .semibold))
            .tracking(1.8)
            .textCase(.uppercase)
            .foregroundStyle(.axTertiary)
    }

    /// Tab-root screen title: 32pt heavy display, tight tracking.
    func axScreenTitle() -> some View {
        self
            .font(.axDisplay(32, .heavy))
            .tracking(-0.96)
            .foregroundStyle(.axPrimary)
    }
}
