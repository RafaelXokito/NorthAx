import SwiftUI

struct GarminConnectView: View {
    @Environment(AthleteStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                statusCard
                if store.garmin.connectionState.isConnected {
                    activityList
                } else {
                    aboutCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color.axBackground)
        .navigationTitle("Garmin Connect")
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
                    Text(store.garmin.connectionState.connectedName ?? "Garmin Connect")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(store.garmin.connectionState.displayLabel)
                        .font(.subheadline)
                        .foregroundStyle(statusColor)
                }

                Spacer()

                if store.garmin.isSyncing {
                    ProgressView()
                        .tint(.axAccent)
                }
            }

            if store.garmin.connectionState.isConnected {
                HStack(spacing: 10) {
                    Button {
                        Task { await store.garmin.syncActivities() }
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
                        store.garmin.disconnect()
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
                    Task { await store.garmin.connect() }
                } label: {
                    HStack(spacing: 8) {
                        if case .connecting = store.garmin.connectionState {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "link")
                        }
                        Text(store.garmin.connectionState == .connecting ? "Connecting…" : "Connect to Garmin")
                    }
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.axAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(store.garmin.connectionState == .connecting)
            }
        }
        .padding(20)
        .background(Color.axSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.axBorder, lineWidth: 1))
    }

    private var statusColor: Color {
        switch store.garmin.connectionState {
        case .connected:     return .axGreen
        case .connecting:    return .axAccent
        case .disconnected:  return .axSecondary
        case .error:         return .axRed
        }
    }

    private var statusIcon: String {
        switch store.garmin.connectionState {
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
                ForEach(store.garmin.syncedActivities) { activity in
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
                infoRow(icon: "arrow.down.circle", text: "Automatically imports your rides, runs, and gym sessions from Garmin Connect")
                infoRow(icon: "chart.line.uptrend.xyaxis", text: "Uses your training history to improve readiness calculations and load tracking")
                infoRow(icon: "calendar.badge.plus", text: "Pushes planned sessions to your Garmin device as structured workouts")
                infoRow(icon: "lock.shield", text: "Connection requires authorisation through Garmin's secure OAuth flow — your credentials are never stored in the app")
            }
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
