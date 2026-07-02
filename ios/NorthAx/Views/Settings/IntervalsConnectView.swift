import SwiftUI

struct IntervalsConnectView: View {
    @Environment(AthleteStore.self) private var store
    @State private var athleteId: String = ""
    @State private var apiKey: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                statusCard
                if store.intervals.connectionState.isConnected {
                    activityList
                } else {
                    aboutCard
                    apiKeyCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color.axBackground)
        .navigationTitle("intervals.icu")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .scrollIndicators(.hidden)
    }

    // MARK: - Status card

    private var statusCard: some View {
        AxCard(radius: 20, padding: 20) {
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(statusColor.opacity(0.15))
                            .frame(width: 52, height: 52)
                        Image(systemName: statusIcon)
                            .font(.title3)
                            .foregroundStyle(statusColor)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.intervals.connectionState.connectedName ?? "intervals.icu")
                            .font(.axDisplay(16, .bold))
                            .foregroundStyle(.axPrimary)
                        Text(store.intervals.connectionState.displayLabel.uppercased())
                            .font(.axMono(10, .semibold))
                            .tracking(0.8)
                            .foregroundStyle(statusColor)
                    }

                    Spacer()

                    if store.intervals.isSyncing {
                        ProgressView()
                            .tint(.axAccent)
                    }
                }

                if store.intervals.connectionState.isConnected {
                    HStack(spacing: 10) {
                        Button {
                            Task { await store.intervals.syncActivities(); await store.loadActivities() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                Text("Sync Now")
                            }
                            .font(.axDisplay(14, .semibold))
                            .foregroundStyle(.axAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.axAccent.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.axAccent.opacity(0.25), lineWidth: 1))
                        }

                        Button {
                            store.intervals.disconnect()
                        } label: {
                            Text("Disconnect")
                                .font(.axDisplay(14, .semibold))
                                .foregroundStyle(.axRed)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Color.axRed.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.axRed.opacity(0.2), lineWidth: 1))
                        }
                    }
                } else {
                    Button {
                        Task { await store.intervals.connect(); await store.loadActivities() }
                    } label: {
                        HStack(spacing: 8) {
                            if case .connecting = store.intervals.connectionState {
                                ProgressView().tint(.axBackground)
                            } else {
                                Image(systemName: "link")
                            }
                            Text(store.intervals.connectionState == .connecting ? "Connecting…" : "Connect intervals.icu")
                        }
                        .font(.axDisplay(15, .bold))
                        .foregroundStyle(Color.axBackground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.axAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                    .disabled(store.intervals.connectionState == .connecting)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var statusColor: Color {
        switch store.intervals.connectionState {
        case .connected:     return .axGreen
        case .connecting:    return .axAccent
        case .disconnected:  return .axSecondary
        case .error:         return .axRed
        }
    }

    private var statusIcon: String {
        switch store.intervals.connectionState {
        case .connected:     return "checkmark.circle.fill"
        case .connecting:    return "arrow.clockwise"
        case .disconnected:  return "wifi.slash"
        case .error:         return "exclamationmark.circle"
        }
    }

    // MARK: - Activity list

    private var activityList: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("SYNCED ACTIVITIES")

            VStack(spacing: 10) {
                ForEach(store.intervals.syncedActivities) { activity in
                    SyncedActivityRow(activity: activity)
                }
            }
        }
    }

    // MARK: - About card

    private var aboutCard: some View {
        AxCard(radius: 20, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel("HOW IT WORKS")

                VStack(spacing: 12) {
                    infoRow(icon: "arrow.down.circle", text: "Imports your rides, runs, and gym sessions via intervals.icu, which syncs with Garmin")
                    infoRow(icon: "chart.line.uptrend.xyaxis", text: "Uses your wellness (HRV, sleep, resting HR) and training load to drive readiness")
                    infoRow(icon: "calendar.badge.plus", text: "Pushes planned sessions to your Garmin device through the intervals.icu calendar")
                    infoRow(icon: "lock.shield", text: "Connects through intervals.icu's secure OAuth flow — credentials are never stored in the app")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - API-key entry

    private var apiKeyCard: some View {
        AxCard(radius: 20, padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("OR CONNECT WITH AN API KEY")
                Text("Paste your intervals.icu athlete id and API key (Settings → Developer).")
                    .font(.axDisplay(12))
                    .foregroundStyle(.axSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("Athlete id (e.g. i557412)", text: $athleteId)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()

                Button {
                    let id = athleteId.trimmingCharacters(in: .whitespaces)
                    let key = apiKey.trimmingCharacters(in: .whitespaces)
                    Task { await store.intervals.connectWithAPIKey(athleteId: id, apiKey: key) }
                } label: {
                    Text("Connect with API key")
                        .font(.axDisplay(14, .semibold))
                        .foregroundStyle(.axAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.axAccent.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.axAccent.opacity(0.25), lineWidth: 1))
                }
                .disabled(athleteId.isEmpty || apiKey.isEmpty)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

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
