import SwiftUI

// Shared "Instrument" building blocks. These replace the card / pill / tile /
// row recipes that were previously re-implemented inline across the views.

// MARK: - Card

/// Standard surface card: `axSurface` fill + hairline stroke.
/// `highlighted` applies the today's-session treatment (orange border + wash).
struct AxCard<Content: View>: View {
    var radius: CGFloat = 20
    var padding: CGFloat = 18
    var highlighted: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(highlighted ? Color.axAccentWash : Color.axSurface)
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(highlighted ? Color.axAccentBorder : Color.axBorder, lineWidth: 1)
            )
    }
}

// MARK: - Section label

/// Mono uppercase section label above a card group.
struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).axSectionLabel()
    }
}

// MARK: - Pill

/// Capsule badge: mono uppercase text, either on a 14%-tint fill or an outline.
struct AxPill: View {
    enum Style { case tint, outline }

    let text: String
    let color: Color
    var style: Style = .tint

    var body: some View {
        Text(text)
            .font(.axMono(10, .semibold))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(style == .tint ? color.opacity(0.14) : .clear)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(style == .outline ? color.opacity(0.45) : .clear, lineWidth: 1)
            )
    }
}

// MARK: - Icon tile

/// SF Symbol on a 14%-opacity tint of its color.
struct IconTile: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 38
    var radius: CGFloat = 12

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

// MARK: - Nav row

/// Settings-style tappable row: icon tile + title/subtitle + trailing value/chevron,
/// in its own card.
struct NavRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var subtitle: String? = nil
    var subtitleColor: Color = .axSecondary
    var value: String? = nil
    var showChevron: Bool = true
    var isDestructive: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            IconTile(systemName: icon, color: isDestructive ? .axRed : iconColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.axDisplay(15, .semibold))
                    .foregroundStyle(isDestructive ? .axRed : .axPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.axDisplay(12.5))
                        .foregroundStyle(subtitleColor)
                }
            }

            Spacer()

            if let value {
                Text(value)
                    .font(.axMono(12))
                    .foregroundStyle(.axSecondary)
            }

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.axTertiary)
            }
        }
        .padding(16)
        .background(Color.axSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.axBorder, lineWidth: 1))
    }
}

// MARK: - Stat tile

/// Inset stat tile: mono label over a display value (TIME / EFFORT / LOAD, stat strips).
struct StatTile: View {
    let label: String
    let value: String
    var valueColor: Color = .axPrimary

    var body: some View {
        VStack(spacing: 5) {
            Text(label)
                .font(.axMono(9, .semibold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(.axTertiary)
            Text(value)
                .font(.axDisplay(17, .bold))
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.axInset)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Contributor meter

/// Readiness contributor: mono label, thin colored progress bar, mono value.
struct ContributorMeter: View {
    let label: String
    let value: String
    let score: Int   // 0–100
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.axMono(10, .semibold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(.axTertiary)
                .frame(width: 46, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.axInset)
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(min(max(score, 0), 100)) / 100)
                }
            }
            .frame(height: 6)

            Text(value)
                .font(.axMono(11, .semibold))
                .foregroundStyle(.axPrimary)
                .frame(width: 52, alignment: .trailing)
        }
    }
}

// MARK: - Synced activity row

/// Activity list row shared by the intervals.icu and Strava screens.
struct SyncedActivityRow: View {
    let activity: GarminActivity

    var body: some View {
        HStack(spacing: 12) {
            IconTile(systemName: activity.type.domain.icon, color: activity.type.domain.color, size: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(activity.name)
                    .font(.axDisplay(14, .semibold))
                    .foregroundStyle(.axPrimary)
                    .lineLimit(1)
                Text(metaLine)
                    .font(.axMono(10))
                    .tracking(0.4)
                    .foregroundStyle(.axTertiary)
            }

            Spacer()

            Text(AxFormat.relativeDate(activity.startTime))
                .font(.axMono(10))
                .foregroundStyle(.axTertiary)
        }
        .padding(14)
        .background(Color.axSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.axBorder, lineWidth: 1))
    }

    private var metaLine: String {
        var parts = [activity.formattedDuration]
        if let dist = activity.formattedDistance { parts.append(dist) }
        if let hr = activity.avgHeartRate { parts.append("\(hr) bpm") }
        return parts.joined(separator: " · ").uppercased()
    }
}

// MARK: - Formatters

enum AxFormat {
    static func relativeDate(_ date: Date) -> String {
        let days = Int(Date().timeIntervalSince(date) / 86400)
        if days == 0 { return "Today" }
        if days == 1 { return "Yesterday" }
        return "\(days)d ago"
    }
}
