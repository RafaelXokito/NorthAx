import SwiftUI

/// Settings → Integrations hub (Plan §5a). Lists third-party data sources as
/// cards: intervals.icu is live (tap → IntervalsConnectView); the rest are
/// "Coming soon" placeholders.
struct IntegrationsView: View {
    @Environment(AthleteStore.self) private var store

    private struct ComingSoon: Identifiable {
        let id = UUID()
        let name: String
        let icon: String
        let color: Color
    }

    private let comingSoon: [ComingSoon] = [
        ComingSoon(name: "Strava",       icon: "figure.run", color: .axAccent),
        ComingSoon(name: "Wahoo",        icon: "bolt.fill",  color: .axBlue)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    sectionLabel("CONNECTED")
                    intervalsRow
                    appleHealthRow
                }

                VStack(alignment: .leading, spacing: 14) {
                    sectionLabel("COMING SOON")
                    VStack(spacing: 10) {
                        ForEach(comingSoon) { comingSoonRow($0) }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color.axBackground)
        .navigationTitle("Integrations")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .scrollIndicators(.hidden)
    }

    // MARK: - intervals.icu

    private var intervalsRow: some View {
        let state = store.intervals.connectionState
        return NavigationLink(destination: IntervalsConnectView()) {
            HStack(spacing: 14) {
                Image(systemName: "applewatch.watchface")
                    .font(.subheadline)
                    .foregroundStyle(.axAccent)
                    .frame(width: 36, height: 36)
                    .background(Color.axAccent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text("intervals.icu")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(state.displayLabel)
                        .font(.caption)
                        .foregroundStyle(state.isConnected ? .axGreen : .axSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.axTertiary)
            }
            .padding(16)
            .background(Color.axSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.axBorder, lineWidth: 1))
        }
    }

    // MARK: - Apple Health

    private var appleHealthRow: some View {
        let h = store.health
        let connected = h.isAvailable && (h.readEnabled || h.writeEnabled)
        let status = !h.isAvailable ? "Not available"
            : (connected ? "Connected" : "Tap to set up")
        return NavigationLink(destination: AppleHealthView()) {
            HStack(spacing: 14) {
                Image(systemName: "heart.fill")
                    .font(.subheadline)
                    .foregroundStyle(.axRed)
                    .frame(width: 36, height: 36)
                    .background(Color.axRed.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Apple Health")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(connected ? .axGreen : .axSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.axTertiary)
            }
            .padding(16)
            .background(Color.axSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.axBorder, lineWidth: 1))
        }
    }

    // MARK: - Coming soon

    private func comingSoonRow(_ item: ComingSoon) -> some View {
        HStack(spacing: 14) {
            Image(systemName: item.icon)
                .font(.subheadline)
                .foregroundStyle(.axTertiary)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.axSecondary)
                Text("Coming soon")
                    .font(.caption)
                    .foregroundStyle(.axTertiary)
            }

            Spacer()
        }
        .padding(16)
        .background(Color.axSurface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.axBorder, lineWidth: 1))
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.axTertiary)
            .tracking(2)
    }
}

#Preview {
    NavigationStack {
        IntegrationsView()
            .environment(AthleteStore())
    }
}
