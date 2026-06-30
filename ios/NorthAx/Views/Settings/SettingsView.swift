import SwiftUI

struct SettingsView: View {
    @Environment(AthleteStore.self) private var store
    @Environment(AuthService.self) private var auth
    @State private var showSignOutConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                profileSection
                planSection
                integrationsSection
                signOutSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color.axBackground)
        .navigationTitle("Settings")
#if os(iOS)
        .navigationBarTitleDisplayMode(.large)
#endif
        .scrollIndicators(.hidden)
    }

    // MARK: - Profile

    private var profileSection: some View {
        @Bindable var bindable = store
        return VStack(alignment: .leading, spacing: 14) {
            sectionLabel("PROFILE")

            VStack(spacing: 12) {
                settingsRow(icon: "person.circle", label: "Name") {
                    TextField("Your name", text: $bindable.athleteName)
                        .multilineTextAlignment(.trailing)
                        .font(.subheadline)
                        .foregroundStyle(.axPrimary)
                }
            }
            .padding(16)
            .background(Color.axSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.axBorder, lineWidth: 1))
        }
    }

    // MARK: - Plan

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("TRAINING")

            NavigationLink(destination: TrainingPlanView()) {
                navRow(icon: "calendar", iconColor: .axAccent, title: "Plan",
                       subtitle: planSummary)
            }
        }
    }

    private var planSummary: String {
        let n = store.trainingFrequency.totalSessions
        let s = store.trainingFrequency.schedules.count
        if n == 0 { return "No sports enrolled yet" }
        return "\(n) \(n == 1 ? "session" : "sessions")/week · \(s) \(s == 1 ? "sport" : "sports")"
    }

    // MARK: - Integrations

    private var integrationsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("INTEGRATIONS")

            NavigationLink(destination: IntegrationsView()) {
                navRow(icon: "antenna.radiowaves.left.and.right", iconColor: .axAccent,
                       title: "Integrations",
                       subtitle: store.intervals.connectionState.isConnected ? "intervals.icu connected" : "Not connected")
            }
        }
    }

    private func navRow(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(iconColor)
                .frame(width: 36, height: 36)
                .background(iconColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.axSecondary)
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

    // MARK: - Sign Out

    private var signOutSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("ACCOUNT")

            Button {
                showSignOutConfirm = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.subheadline)
                        .foregroundStyle(.axRed)
                        .frame(width: 36, height: 36)
                        .background(Color.axRed.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Text("Sign Out")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.axRed)

                    Spacer()
                }
                .padding(16)
                .background(Color.axSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.axBorder, lineWidth: 1))
            }
        }
        .confirmationDialog("Sign Out", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                store.resetForSignOut()
                auth.signOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your training data stays on this device. You can sign back in at any time.")
        }
    }

    // MARK: - Helpers

    private func settingsRow<Content: View>(icon: String, label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.axAccent)
                .frame(width: 24)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.axSecondary)

            Spacer()

            content()
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.axTertiary)
            .tracking(2)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(AthleteStore())
            .environment(AuthService())
    }
}
