import SwiftUI

struct ContentView: View {
    @State private var authService = AuthService()
    @State private var store = AthleteStore()
    @State private var selectedTab: AppTab = .dashboard

    enum AppTab { case dashboard, coach, metrics, plan, settings }

    var body: some View {
        ZStack {
            if authService.isAuthenticated {
                mainApp
            } else {
                SignInView()
                    .environment(authService)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: authService.currentUser) { _, user in
            if let user {
                store.configure(with: user)
            }
        }
    }

    private var mainApp: some View {
        TabView(selection: $selectedTab) {
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
