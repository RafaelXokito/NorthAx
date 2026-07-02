import SwiftUI

/// Settings → Apple Health (Plan §4). Two independent toggles — read recovery
/// metrics and write completed workouts — plus an authorize action. Handles the
/// HealthKit-unavailable case (e.g. iPad without pairing) with an explanatory
/// disabled state. Styling mirrors IntervalsConnectView.
struct AppleHealthView: View {
    @Environment(AthleteStore.self) private var store

    var body: some View {
        @Bindable var bindable = store
        return ScrollView {
            VStack(spacing: 20) {
                statusCard
                if store.health.isAvailable {
                    togglesCard(bindable)
                    aboutCard
                } else {
                    unavailableCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color.axBackground)
        .navigationTitle("Apple Health")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .scrollIndicators(.hidden)
    }

    // MARK: - Status card

    private var statusCard: some View {
        let available = store.health.isAvailable
        let connected = available && (store.health.readEnabled || store.health.writeEnabled)
        let color: Color = !available ? .axSecondary : (connected ? .axGreen : .axSecondary)
        return AxCard(radius: 20, padding: 20) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(color.opacity(0.15)).frame(width: 52, height: 52)
                    Image(systemName: "heart.fill")
                        .font(.title3)
                        .foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Apple Health")
                        .font(.axDisplay(16, .bold))
                        .foregroundStyle(.axPrimary)
                    Text((!available ? "Not available on this device"
                         : (connected ? "Connected" : "Not connected")).uppercased())
                        .font(.axMono(10, .semibold))
                        .tracking(0.8)
                        .foregroundStyle(color)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Toggles

    private func togglesCard(_ bindable: AthleteStore) -> some View {
        AxCard(radius: 20, padding: 20) {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("PERMISSIONS")

            VStack(spacing: 14) {
                Toggle(isOn: Binding(
                    get: { bindable.health.readEnabled },
                    set: { on in
                        bindable.health.readEnabled = on
                        if on { Task { await authorize() } }
                    }
                )) {
                    toggleLabel("Read health data",
                                "Resting HR, HRV, sleep, VO2 Max, and body metrics — used for readiness when Garmin isn't connected.")
                }
                .tint(.axAccent)

                Rectangle().fill(Color.axBorder).frame(height: 1)

                Toggle(isOn: Binding(
                    get: { bindable.health.writeEnabled },
                    set: { on in
                        bindable.health.writeEnabled = on
                        if on { Task { await authorize() } }
                    }
                )) {
                    toggleLabel("Write completed workouts",
                                "Logs sessions you mark as done to Apple Health as workouts.")
                }
                .tint(.axAccent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func toggleLabel(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.axDisplay(14, .semibold))
                .foregroundStyle(.axPrimary)
            Text(detail)
                .font(.axDisplay(12))
                .foregroundStyle(.axSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - About

    private var aboutCard: some View {
        AxCard(radius: 20, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel("HOW IT WORKS")
                VStack(spacing: 12) {
                    infoRow(icon: "arrow.down.circle", text: "Supplements your readiness with Apple Health metrics when no Garmin/intervals.icu source is connected")
                    infoRow(icon: "arrow.up.circle", text: "Posts your completed sessions back to Apple Health as workouts")
                    infoRow(icon: "lock.shield", text: "Permissions are managed by iOS — you can change them anytime in the Health app")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var unavailableCard: some View {
        AxCard(radius: 20, padding: 20) {
            Text("Apple Health isn't available on this device. This usually means it's an iPad without a paired iPhone or Apple Watch.")
                .font(.axDisplay(13.5))
                .foregroundStyle(.axSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Actions

    private func authorize() async {
        try? await store.health.requestAuthorization()
        // Reading just became available — refresh so readiness picks it up.
        await store.loadMetricsAndReadiness()
    }

    // MARK: - Helpers

    private func infoRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.axAccent)
                .frame(width: 24)
            Text(text)
                .font(.axDisplay(13))
                .foregroundStyle(.axSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
