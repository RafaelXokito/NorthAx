import SwiftUI

/// Settings → Integrations → Strava (§13). Personal single-athlete connect: one
/// tap calls the backend, which uses its stored refresh token — no web redirect.
struct StravaConnectView: View {
    @Environment(AthleteStore.self) private var store

    var body: some View {
        let state = store.strava.connectionState
        ScrollView {
            VStack(spacing: 20) {
                header(state)

                if state.isConnected {
                    connectedCard(state)
                    if !store.strava.syncedActivities.isEmpty {
                        syncedActivitiesList
                    }
                } else {
                    connectCard(state)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color.axBackground)
        .navigationTitle("Strava")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .scrollIndicators(.hidden)
        .task { await store.strava.refreshStatus() }
    }

    private func header(_ state: IntervalsConnectionState) -> some View {
        VStack(spacing: 12) {
            IconTile(systemName: "figure.run", color: .axAccent, size: 76, radius: 20)
            Text("Strava")
                .font(.axDisplay(20, .heavy))
                .tracking(-0.4)
                .foregroundStyle(.axPrimary)
            Text(state.displayLabel.uppercased())
                .font(.axMono(10, .semibold))
                .tracking(0.8)
                .foregroundStyle(state.isConnected ? .axGreen : .axSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    private func connectCard(_ state: IntervalsConnectionState) -> some View {
        AxCard(radius: 20, padding: 20) {
            VStack(spacing: 16) {
                Text("Connect Strava to import your activities — runs, rides, swims and more — so completed workouts are matched to your plan automatically.")
                    .font(.axDisplay(13.5))
                    .foregroundStyle(.axSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                if case .error(let msg) = state {
                    Text(msg)
                        .font(.axDisplay(12))
                        .foregroundStyle(.axRed)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task {
                        await store.strava.connect()
                        await store.loadActivities()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if state == .connecting { ProgressView().controlSize(.small).tint(.axBackground) }
                        Text(state == .connecting ? "Connecting…" : "Connect Strava")
                    }
                    .font(.axDisplay(15, .bold))
                    .foregroundStyle(Color.axBackground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.axAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .disabled(state == .connecting)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func connectedCard(_ state: IntervalsConnectionState) -> some View {
        AxCard(radius: 20, padding: 20) {
            VStack(spacing: 14) {
                Button {
                    Task {
                        await store.strava.sync()
                        await store.loadActivities()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if store.strava.isSyncing { ProgressView().controlSize(.small).tint(.axAccent) }
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text(store.strava.isSyncing ? "Syncing…" : "Sync now")
                    }
                    .font(.axDisplay(14, .semibold))
                    .foregroundStyle(.axAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.axAccent.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.axAccent.opacity(0.25), lineWidth: 1))
                }
                .disabled(store.strava.isSyncing)

                Button(role: .destructive) {
                    store.strava.disconnect()
                } label: {
                    Text("Disconnect")
                        .font(.axDisplay(14, .semibold))
                        .foregroundStyle(.axRed)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Color.axRed.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.axRed.opacity(0.2), lineWidth: 1))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var syncedActivitiesList: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("SYNCED ACTIVITIES")
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 10) {
                ForEach(store.strava.syncedActivities) { activity in
                    SyncedActivityRow(activity: activity)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        StravaConnectView().environment(AthleteStore())
    }
}
