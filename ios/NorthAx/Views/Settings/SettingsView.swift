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
        return VStack(alignment: .leading, spacing: 12) {
            SectionLabel("PROFILE")

            AxCard(radius: 16, padding: 16) {
                settingsRow(icon: "person.circle", label: "Name") {
                    TextField("Your name", text: $bindable.athleteName)
                        .multilineTextAlignment(.trailing)
                        .font(.axDisplay(14, .semibold))
                        .foregroundStyle(.axPrimary)
                }
            }
        }
    }

    // MARK: - Plan

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("TRAINING")

            NavigationLink(destination: TrainingPlanView()) {
                NavRow(icon: "calendar", iconColor: .axAccent, title: "Plan",
                       subtitle: planSummary)
            }
            .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("INTEGRATIONS")

            NavigationLink(destination: IntegrationsView()) {
                NavRow(icon: "antenna.radiowaves.left.and.right", iconColor: .axAccent,
                       title: "Integrations",
                       subtitle: store.intervals.connectionState.isConnected ? "intervals.icu connected" : "Not connected")
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Sign Out

    private var signOutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("ACCOUNT")

            Button {
                showSignOutConfirm = true
            } label: {
                NavRow(icon: "rectangle.portrait.and.arrow.right", iconColor: .axRed,
                       title: "Sign Out", showChevron: false, isDestructive: true)
            }
            .buttonStyle(.plain)
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
                .font(.axDisplay(13.5))
                .foregroundStyle(.axSecondary)

            Spacer()

            content()
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(AthleteStore())
            .environment(AuthService())
    }
}
