import SwiftUI

struct SettingsView: View {
    @Environment(AthleteStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                profileSection
                garminSection
                frequencySection
                strengthSection
                domainsSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color.axBackground.ignoresSafeArea())
        .navigationTitle("Settings")
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

    // MARK: - Garmin

    private var garminSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("INTEGRATIONS")

            NavigationLink(destination: GarminConnectView()) {
                HStack(spacing: 14) {
                    Image(systemName: "applewatch.watchface")
                        .font(.subheadline)
                        .foregroundStyle(.axAccent)
                        .frame(width: 36, height: 36)
                        .background(Color.axAccent.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Garmin Connect")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(store.garmin.connectionState.displayLabel)
                            .font(.caption)
                            .foregroundStyle(store.garmin.connectionState.isConnected ? .axGreen : .axSecondary)
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
        }
    }

    // MARK: - Training frequency

    private var frequencySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("TRAINING SCHEDULE")

            NavigationLink(destination: TrainingFrequencyView()) {
                HStack(spacing: 14) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.subheadline)
                        .foregroundStyle(.axBlue)
                        .frame(width: 36, height: 36)
                        .background(Color.axBlue.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Training Frequency")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        let n = store.trainingFrequency.totalTrainingDays
                        Text("\(n) training \(n == 1 ? "day" : "days") per week")
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
        }
    }

    // MARK: - Strength / split

    private var strengthSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("STRENGTH TRAINING")

            NavigationLink(destination: MuscleGroupSplitView()) {
                HStack(spacing: 14) {
                    Image(systemName: "dumbbell")
                        .font(.subheadline)
                        .foregroundStyle(.axRed)
                        .frame(width: 36, height: 36)
                        .background(Color.axRed.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Muscle Group Split")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(todaySplitSummary)
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
        }
    }

    private var todaySplitSummary: String {
        let weekday = Calendar.current.component(.weekday, from: Date())
        let split   = store.muscleGroupSplit.split(forCalendarWeekday: weekday)
        return "Today: \(split.displayName)"
    }

    // MARK: - Enabled domains

    private var domainsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("ACTIVE TRAINING DOMAINS")

            VStack(spacing: 10) {
                ForEach(TrainingDomain.allCases) { domain in
                    domainRow(domain)
                }
            }
            .padding(16)
            .background(Color.axSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.axBorder, lineWidth: 1))
        }
    }

    private func domainRow(_ domain: TrainingDomain) -> some View {
        let isEnabled = store.enabledDomains.contains(domain)

        return Button {
            if isEnabled {
                store.enabledDomains.removeAll { $0 == domain }
            } else {
                store.enabledDomains.append(domain)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: domain.icon)
                    .font(.subheadline)
                    .foregroundStyle(isEnabled ? domain.color : .axTertiary)
                    .frame(width: 32)

                Text(domain.rawValue)
                    .font(.subheadline)
                    .foregroundStyle(isEnabled ? .axPrimary : .axSecondary)

                Spacer()

                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isEnabled ? domain.color : .axTertiary)
            }
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
    }
}
