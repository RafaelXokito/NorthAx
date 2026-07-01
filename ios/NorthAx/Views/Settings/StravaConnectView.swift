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
            Image(systemName: "figure.run")
                .font(.system(size: 34))
                .foregroundStyle(.axAccent)
                .frame(width: 76, height: 76)
                .background(Color.axAccent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 20))
            Text("Strava")
                .font(.title2.bold()).foregroundStyle(.white)
            Text(state.displayLabel)
                .font(.subheadline)
                .foregroundStyle(state.isConnected ? .axGreen : .axSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    private func connectCard(_ state: IntervalsConnectionState) -> some View {
        VStack(spacing: 16) {
            Text("Connect Strava to import your activities — runs, rides, swims and more — so completed workouts are matched to your plan automatically.")
                .font(.subheadline)
                .foregroundStyle(.axSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            if case .error(let msg) = state {
                Text(msg)
                    .font(.caption)
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
                    if state == .connecting { ProgressView().controlSize(.small).tint(.black) }
                    Text(state == .connecting ? "Connecting…" : "Connect Strava")
                }
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.axAccent)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(state == .connecting)
        }
        .padding(20)
        .background(Color.axSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.axBorder, lineWidth: 1))
    }

    private func connectedCard(_ state: IntervalsConnectionState) -> some View {
        VStack(spacing: 14) {
            Button {
                Task {
                    await store.strava.sync()
                    await store.loadActivities()
                }
            } label: {
                HStack(spacing: 8) {
                    if store.strava.isSyncing { ProgressView().controlSize(.small).tint(.black) }
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text(store.strava.isSyncing ? "Syncing…" : "Sync now")
                }
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.axAccent)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(store.strava.isSyncing)

            Button(role: .destructive) {
                store.strava.disconnect()
            } label: {
                Text("Disconnect")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.axRed)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Color.axRed.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(20)
        .background(Color.axSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.axBorder, lineWidth: 1))
    }
}

#Preview {
    NavigationStack {
        StravaConnectView().environment(AthleteStore())
    }
}
