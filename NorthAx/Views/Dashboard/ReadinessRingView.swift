import SwiftUI

struct ReadinessRingView: View {
    let score: Int
    let status: DailyReadiness.Status

    @State private var progress: Double = 0

    var ringColor: Color {
        switch status {
        case .peak:     return .axAccent
        case .high:     return .axGreen
        case .moderate: return .axBlue
        case .low:      return Color(red: 1.0, green: 0.7, blue: 0.2)
        case .rest:     return .axRed
        }
    }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 14)

            // Fill
            Circle()
                .trim(from: 0, to: progress * Double(score) / 100)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 1.4, bounce: 0.15), value: progress)

            // Score label
            VStack(spacing: 2) {
                Text("\(score)")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())

                Text("READINESS")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .tracking(2.5)
            }
        }
        .onAppear {
            withAnimation { progress = 1 }
        }
    }
}

#Preview {
    ReadinessRingView(score: 87, status: .peak)
        .frame(width: 200, height: 200)
        .background(Color.axBackground)
}
