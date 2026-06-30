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

                    // Steppers
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

    private func onboardingDomainRow(_ domain: TrainingDomain) -> some View {
        let current = localFrequency.days(for: domain)
        return HStack(spacing: 12) {
            Image(systemName: domain.icon)
                .font(.subheadline)
                .foregroundStyle(current > 0 ? domain.color : .axTertiary)
                .frame(width: 32, height: 32)
                .background((current > 0 ? domain.color : Color.white).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(domain.rawValue)
                .font(.subheadline)
                .foregroundStyle(current > 0 ? .axPrimary : .axSecondary)

            Spacer()

            HStack(spacing: 0) {
                Button {
                    if current > 0 { localFrequency.setDays(current - 1, for: domain) }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(current > 0 ? .axPrimary : .axTertiary)
                        .frame(width: 36, height: 36)
                }
                .disabled(current == 0)

                Text("\(current)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(current > 0 ? domain.color : .axTertiary)
                    .frame(width: 28)
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.2), value: current)

                Button {
                    if localFrequency.totalTrainingDays < 6 {
                        localFrequency.setDays(current + 1, for: domain)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(localFrequency.totalTrainingDays < 6 ? .axPrimary : .axTertiary)
                        .frame(width: 36, height: 36)
                }
                .disabled(localFrequency.totalTrainingDays >= 6)
            }
            .background(Color.white.opacity(0.05))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

#Preview {
    FrequencyOnboardingView()
        .environment(AthleteStore())
}
