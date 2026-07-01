import SwiftUI

/// Main tab identity. Top-level (not nested in ContentView) so `AthleteStore`
/// can hold the current selection and buttons elsewhere can deep-link to a tab.
enum AppTab { case dashboard, coach, metrics, plan, settings }

struct ContentView: View {
    @State private var authService = AuthService()
    @State private var store = AthleteStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if authService.isAuthenticated {
                mainApp
            } else {
                SignInView()
                    .environment(authService)
            }

            if store.isGeneratingPlan {
                PlanGeneratingView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.isGeneratingPlan)
        .preferredColorScheme(.dark)
        // `initial: true` so a session restored during AuthService.init() (which
        // sets currentUser before this view starts observing) still triggers the
        // profile/data load and name — not just fresh logins.
        .onChange(of: authService.currentUser, initial: true) { _, user in
            if let user {
                store.configure(with: user)
            }
        }
        // First foreground of a new day pre-fetches AI switch suggestions (§9).
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.prefetchDailySuggestionsIfNeeded() }
        }
    }

    private var mainApp: some View {
        TabView(selection: Binding(get: { store.selectedTab }, set: { store.selectedTab = $0 })) {
            Tab("Today", systemImage: "house.fill", value: AppTab.dashboard) {
                DashboardView()
            }

            Tab("Coach", systemImage: "bubble.left.and.bubble.right", value: AppTab.coach) {
                NavigationStack {
                    CoachView()
                }
            }

            Tab("Metrics", systemImage: "chart.xyaxis.line", value: AppTab.metrics) {
                NavigationStack {
                    MetricsView()
                }
            }

            Tab("Plan", systemImage: "calendar", value: AppTab.plan) {
                NavigationStack {
                    PlanView()
                }
            }

            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack {
                    SettingsView()
                }
            }
        }
        .tabViewStyle(.tabBarOnly)
        .environment(store)
        .environment(authService)
        .sheet(isPresented: Binding(
            get: { !store.hasSetFrequency },
            set: { if !$0 { store.hasSetFrequency = true } }
        )) {
            FrequencyOnboardingView()
                .environment(store)
        }
    }
}

#Preview {
    ContentView()
}
