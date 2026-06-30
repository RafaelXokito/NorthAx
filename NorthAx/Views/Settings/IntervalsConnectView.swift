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
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(store.intervals.connectionState.displayLabel)
                        .font(.subheadline)
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
                        Task { await store.intervals.syncActivities() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text("Sync Now")
                        }
                        .font(.subheadline.weight(.semibold))
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
                            .font(.subheadline.weight(.semibold))
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
                    Task { await store.intervals.connect() }
                } label: {
                    HStack(spacing: 8) {
                        if case .connecting = store.intervals.connectionState {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "link")
                        }
                        Text(store.intervals.connectionState == .connecting ? "Connecting…" : "Connect intervals.icu")
                    }
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.axAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(store.intervals.connectionState == .connecting)
            }
        }
        .padding(20)
        .background(Color.axSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.axBorder, lineWidth: 1))
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
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("SYNCED ACTIVITIES")

            VStack(spacing: 10) {
                ForEach(store.intervals.syncedActivities) { activity in
                    activityRow(activity)
                }
            }
        }
    }

    private func activityRow(_ activity: GarminActivity) -> some View {
        HStack(spacing: 12) {
            Image(systemName: activity.type.domain.icon)
                .font(.subheadline)
                .foregroundStyle(activity.type.domain.color)
                .frame(width: 36, height: 36)
                .background(activity.type.domain.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                HStack(spacing: 6) {
                    Text(activity.formattedDuration)
                    if let dist = activity.formattedDistance {
                        Text("·")
                        Text(dist)
                    }
                    if let hr = activity.avgHeartRate {
                        Text("·")
                        Text("\(hr) bpm avg")
                    }
                }
                .font(.caption)
                .foregroundStyle(.axTertiary)
            }

            Spacer()

            Text(relativeDate(activity.startTime))
                .font(.caption)
                .foregroundStyle(.axTertiary)
        }
        .padding(14)
        .background(Color.axSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.axBorder, lineWidth: 1))
    }

    // MARK: - About card

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("HOW IT WORKS")

            VStack(spacing: 12) {
                infoRow(icon: "arrow.down.circle", text: "Imports your rides, runs, and gym sessions via intervals.icu, which syncs with Garmin")
                infoRow(icon: "chart.line.uptrend.xyaxis", text: "Uses your wellness (HRV, sleep, resting HR) and training load to drive readiness")
                infoRow(icon: "calendar.badge.plus", text: "Pushes planned sessions to your Garmin device through the intervals.icu calendar")
                infoRow(icon: "lock.shield", text: "Connects through intervals.icu's secure OAuth flow — credentials are never stored in the app")
            }
        }
        .padding(20)
        .background(Color.axSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.axBorder, lineWidth: 1))
    }

    // MARK: - API-key entry

    private var apiKeyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("OR CONNECT WITH AN API KEY")
            Text("Paste your intervals.icu athlete id and API key (Settings → Developer).")
                .font(.caption)
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
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.axAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.axAccent.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.axAccent.opacity(0.25), lineWidth: 1))
            }
            .disabled(athleteId.isEmpty || apiKey.isEmpty)
        }
        .padding(20)
        .background(Color.axSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.axBorder, lineWidth: 1))
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.axAccent)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.axSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.axTertiary)
            .tracking(2)
    }

    private func relativeDate(_ date: Date) -> String {
        let days = Int(Date().timeIntervalSince(date) / 86400)
        if days == 0 { return "Today" }
        if days == 1 { return "Yesterday" }
        return "\(days)d ago"
    }
}
