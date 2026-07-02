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
        ComingSoon(name: "Wahoo",        icon: "bolt.fill",  color: .axBlue)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel("CONNECTED")
                    intervalsRow
                    stravaRow
                    appleHealthRow
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel("DATA PRIORITY")
                    dataPriorityRow
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel("COMING SOON")
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

    // MARK: - Rows

    private var intervalsRow: some View {
        let state = store.intervals.connectionState
        return NavigationLink(destination: IntervalsConnectView()) {
            NavRow(icon: "applewatch.watchface", iconColor: .axAccent,
                   title: "intervals.icu",
                   subtitle: state.displayLabel,
                   subtitleColor: state.isConnected ? .axGreen : .axSecondary)
        }
        .buttonStyle(.plain)
    }

    private var stravaRow: some View {
        let state = store.strava.connectionState
        return NavigationLink(destination: StravaConnectView()) {
            NavRow(icon: "figure.run", iconColor: .axAccent,
                   title: "Strava",
                   subtitle: state.displayLabel,
                   subtitleColor: state.isConnected ? .axGreen : .axSecondary)
        }
        .buttonStyle(.plain)
    }

    private var appleHealthRow: some View {
        let h = store.health
        let connected = h.isAvailable && (h.readEnabled || h.writeEnabled)
        let status = !h.isAvailable ? "Not available"
            : (connected ? "Connected" : "Tap to set up")
        return NavigationLink(destination: AppleHealthView()) {
            NavRow(icon: "heart.fill", iconColor: .axRed,
                   title: "Apple Health",
                   subtitle: status,
                   subtitleColor: connected ? .axGreen : .axSecondary)
        }
        .buttonStyle(.plain)
    }

    private var dataPriorityRow: some View {
        NavigationLink(destination: MetricPriorityView()) {
            NavRow(icon: "slider.horizontal.3", iconColor: .axGreen,
                   title: "Source priority",
                   subtitle: "Choose which source wins per metric")
        }
        .buttonStyle(.plain)
    }

    // MARK: - Coming soon

    private func comingSoonRow(_ item: ComingSoon) -> some View {
        NavRow(icon: item.icon, iconColor: .axTertiary,
               title: item.name,
               subtitle: "Coming soon",
               showChevron: false)
            .opacity(0.6)
    }
}

#Preview {
    NavigationStack {
        IntegrationsView()
            .environment(AthleteStore())
    }
}
