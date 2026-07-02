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
        // First foreground of a new day pre-fetches AI switch suggestions (§9);
        // foregrounding also pulls the latest from connected sources (throttled).
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.prefetchDailySuggestionsIfNeeded()
                store.syncConnectedSourcesIfNeeded()
            }
        }
    }

    private var mainApp: some View {
        TabView(selection: Binding(get: { store.selectedTab }, set: { store.selectedTab = $0 })) {
            Tab("Today", systemImage: "house.fill", value: AppTab.dashboard) {
                DashboardView()
                    .toolbar(.hidden, for: .tabBar)
            }

            // Coach tab hidden for now — kept for later (CoachView + AppTab.coach remain).
            // Tab("Coach", systemImage: "bubble.left.and.bubble.right", value: AppTab.coach) {
            //     NavigationStack {
            //         CoachView()
            //     }
            // }

            Tab("Metrics", systemImage: "chart.xyaxis.line", value: AppTab.metrics) {
                NavigationStack {
                    MetricsView()
                }
                .toolbar(.hidden, for: .tabBar)
            }

            Tab("Plan", systemImage: "calendar", value: AppTab.plan) {
                NavigationStack {
                    PlanView()
                }
                .toolbar(.hidden, for: .tabBar)
            }

            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack {
                    SettingsView()
                }
                .toolbar(.hidden, for: .tabBar)
            }
        }
        .tabViewStyle(.tabBarOnly)
        .tint(.axAccent)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AxTabBar(selection: Binding(get: { store.selectedTab }, set: { store.selectedTab = $0 }))
        }
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

/// "Instrument" tab bar: flat line icons over mono uppercase labels on a
/// blurred near-black strip with a top hairline (design §Global chrome).
private struct AxTabBar: View {
    @Binding var selection: AppTab

    private let items: [(tab: AppTab, icon: String, label: String)] = [
        (.dashboard, "house",             "Today"),
        (.metrics,   "chart.xyaxis.line", "Metrics"),
        (.plan,      "calendar",          "Plan"),
        (.settings,  "gearshape",         "Settings"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.tab) { item in
                Button { selection = item.tab } label: {
                    VStack(spacing: 5) {
                        Image(systemName: item.icon)
                            .font(.system(size: 21, weight: .medium))
                        Text(item.label)
                            .font(.axMono(9, .semibold))
                            .tracking(1.2)
                            .textCase(.uppercase)
                    }
                    .foregroundStyle(selection == item.tab ? Color.axAccent : Color.axPrimary.opacity(0.38))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.axBackground.opacity(0.6)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Color.axBorder).frame(height: 1)
        }
    }
}

#Preview {
    ContentView()
}
