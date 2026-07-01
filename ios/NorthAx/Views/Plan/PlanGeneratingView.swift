import SwiftUI

/// Full-screen overlay shown while the AI planner generates the next two weeks.
/// Presented from `ContentView` whenever `store.isGeneratingPlan` is true.
struct PlanGeneratingView: View {
    var body: some View {
        ZStack {
            Color.axBackground.opacity(0.92).ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.axAccent)

                VStack(spacing: 6) {
                    Text("Building your plan")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Your coach is tailoring the next two weeks to your schedule, recent training, and recovery.")
                        .font(.subheadline)
                        .foregroundStyle(.axSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 40)
            }
        }
        .transition(.opacity)
    }
}

#Preview {
    PlanGeneratingView()
}
