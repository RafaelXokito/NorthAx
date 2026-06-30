import SwiftUI

/// First-launch sheet that collects training frequency before showing the main app.
struct FrequencyOnboardingView: View {
    @Environment(AthleteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var localFrequency: TrainingFrequency = .defaultFrequency
    @State private var step: OnboardingStep = .welcome

    enum OnboardingStep { case welcome, frequency }

    private let domains: [TrainingDomain] = [.cycling, .running, .strength, .swimming, .triathlon, .mobility]

    var body: some View {
        ZStack {
            Color.axBackground.ignoresSafeArea()

            switch step {
            case .welcome: welcomeStep
            case .frequency: frequencyStep
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Welcome step

    private var welcomeStep: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "figure.run.circle")
                    .font(.system(size: 64))
                    .foregroundStyle(.axAccent)

                Text("NorthAx")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Your intelligent training\noperating system.")
                    .font(.title3)
                    .foregroundStyle(.axSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                featureRow(icon: "waveform.path.ecg",     text: "Reads your HRV, sleep, and load every morning")
                featureRow(icon: "brain.head.profile",    text: "Explains every recommendation in plain language")
                featureRow(icon: "calendar.badge.plus",   text: "Builds and adjusts your training plan automatically")
                featureRow(icon: "arrow.left.arrow.right",text: "Adapts when you need to swap activities")
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                withAnimation(.spring(duration: 0.4)) { step = .frequency }
            } label: {
                Text("Let's build your plan")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.axAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)))
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.axAccent)
                .frame(width: 32)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.axSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    // MARK: - Frequency step

    private var frequencyStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text("How do you want to train?")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)

                        Text("Set your weekly sessions per sport. You can always change this in Settings.")
                            .font(.subheadline)
                            .foregroundStyle(.axSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }
                    .padding(.top, 32)

                    // Per-sport weekday toggles
                    VStack(spacing: 0) {
                        ForEach(domains) { domain in
                            onboardingDomainRow(domain)
                            if domain != domains.last {
                                Rectangle().fill(Color.axBorder).frame(height: 1).padding(.horizontal, 16)
                            }
                        }
                    }
                    .background(Color.axSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.axBorder, lineWidth: 1))
                    .padding(.horizontal, 24)

                    // Summary
                    let n = localFrequency.totalTrainingDays
                    let r = localFrequency.restDaysPerWeek
                    Text("\(n) training \(n == 1 ? "day" : "days") · \(r) rest \(r == 1 ? "day" : "days") per week")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.axSecondary)
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.25), value: n)
                }
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)

            // Sticky CTA
            VStack(spacing: 0) {
                Rectangle().fill(Color.axBackground).frame(height: 1)
                Button {
                    store.trainingFrequency = localFrequency
                    store.hasSetFrequency = true
                    dismiss()  // closes the sheet when presented from the Plan tab
                } label: {
                    Text(localFrequency.totalTrainingDays == 0 ? "Skip for now" : "Build My Plan →")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(localFrequency.totalTrainingDays == 0 ? Color.axSecondary : Color.axAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .background(Color.axBackground)
                .animation(.easeInOut(duration: 0.2), value: localFrequency.totalTrainingDays)
            }
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
    }

    // 0=Mon … 6=Sun (wire weekday encoding).
    private let weekdayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    private func onboardingDomainRow(_ domain: TrainingDomain) -> some View {
        let days = localFrequency.weekdays(for: domain)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: domain.icon)
                    .font(.subheadline)
                    .foregroundStyle(days.isEmpty ? .axTertiary : domain.color)
                    .frame(width: 32, height: 32)
                    .background((days.isEmpty ? Color.white : domain.color).opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(domain.rawValue)
                    .font(.subheadline)
                    .foregroundStyle(days.isEmpty ? .axSecondary : .axPrimary)

                Spacer()
            }

            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { wd in
                    let on = days.contains(wd)
                    Button {
                        localFrequency.toggle(wd, for: domain)
                    } label: {
                        Text(weekdayLabels[wd])
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(on ? .black : .axSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(on ? domain.color : Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    FrequencyOnboardingView()
        .environment(AthleteStore())
}
