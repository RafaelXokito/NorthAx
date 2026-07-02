import SwiftUI

/// 270° tachometer readiness gauge: outer tick ring, glowing arc + endpoint dot,
/// count-up numeral. The arc opens at the bottom (starts at 135°, sweeps 270°).
struct ReadinessRingView: View {
    let score: Int
    let status: DailyReadiness.Status

    @State private var fraction: Double = 0

    var body: some View {
        TachometerGauge(fraction: fraction, color: status.color)
            .onAppear { animateToScore() }
            .onChange(of: score) { animateToScore() }
    }

    private func animateToScore() {
        // easeOutCubic, matching the design's ~1150ms mount animation.
        withAnimation(.timingCurve(0.33, 1, 0.68, 1, duration: 1.15)) {
            fraction = Double(score) / 100
        }
    }
}

/// `Animatable` so the arc, tick threshold, endpoint dot, and numeral all track
/// the same interpolated fraction — the numeral counts up rather than jumping.
private struct TachometerGauge: View, Animatable {
    var fraction: Double
    let color: Color

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    private let startAngle = 135.0   // 0° = 3 o'clock, clockwise
    private let sweep = 270.0
    private let tickCount = 38
    private let lineWidth: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let tickRadius = side / 2 - 3                       // ticks are 6pt tall
            let arcRadius = tickRadius - 11 - lineWidth / 2
            let numeralSize = min(74, side * 0.34)

            ZStack {
                // Tick ring
                ForEach(0..<tickCount, id: \.self) { i in
                    let lit = fraction > 0 && Double(i) / Double(tickCount - 1) <= fraction
                    Capsule()
                        .fill(lit ? color : Color.white.opacity(0.12))
                        .frame(width: 2, height: 6)
                        .offset(y: -tickRadius)
                        .rotationEffect(.degrees(startAngle + 90 + sweep * Double(i) / Double(tickCount - 1)))
                }

                // Track
                Circle()
                    .trim(from: 0, to: sweep / 360)
                    .stroke(Color.white.opacity(0.07), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(startAngle))
                    .frame(width: arcRadius * 2, height: arcRadius * 2)

                // Value arc
                Circle()
                    .trim(from: 0, to: sweep / 360 * fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(startAngle))
                    .frame(width: arcRadius * 2, height: arcRadius * 2)
                    .shadow(color: color.opacity(0.4), radius: 8)

                // Endpoint dot
                Circle()
                    .fill(color)
                    .frame(width: 11, height: 11)
                    .offset(y: -arcRadius)
                    .rotationEffect(.degrees(startAngle + 90 + sweep * fraction))
                    .shadow(color: color.opacity(0.4), radius: 8)

                // Numeral
                VStack(spacing: 2) {
                    Text("\(Int((fraction * 100).rounded()))")
                        .font(.axDisplay(numeralSize, .heavy))
                        .tracking(-0.04 * numeralSize)
                        .foregroundStyle(.axPrimary)

                    Text("READINESS")
                        .font(.axMono(10, .semibold))
                        .tracking(1.8)
                        .foregroundStyle(.axTertiary)
                }
                .offset(x: 0.02 * numeralSize)   // optically recenter the negative tracking
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

#Preview {
    ReadinessRingView(score: 87, status: .high)
        .frame(width: 220, height: 220)
        .padding(40)
        .background(Color.axBackground)
}
