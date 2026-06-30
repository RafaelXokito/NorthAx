import SwiftUI

struct TrainingFrequencyView: View {
    @Environment(AthleteStore.self) private var store
    @State private var localFrequency: TrainingFrequency = .empty
    @State private var hasChanges = false

    private let allDomains: [TrainingDomain] = [.cycling, .running, .strength, .swimming, .triathlon, .mobility]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                explanation
                domainSteppers
                summary
                weekPreview
                if store.trainingFrequency.isOverloaded { overloadWarning }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color.axBackground)
        .navigationTitle("Training Frequency")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .scrollIndicators(.hidden)
        .onAppear { localFrequency = store.trainingFrequency }
        .onChange(of: localFrequency) { _, new in
            store.trainingFrequency = new
            hasChanges = true
        }
    }

    // MARK: - Explanation

    private var explanation: some View {
        Text("Set how many days per week you aim to train for each sport. NorthAx uses this to build your weekly schedule and adjust it forward whenever targets change.")
            .font(.subheadline)
            .foregroundStyle(.axSecondary)
            .lineSpacing(4)
    }

    // MARK: - Domain steppers

    private var domainSteppers: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("SESSIONS PER WEEK")

            VStack(spacing: 0) {
                ForEach(allDomains) { domain in
                    domainRow(domain)
                    if domain != allDomains.last {
                        Rectangle().fill(Color.axBorder).frame(height: 1).padding(.horizontal, 16)
                    }
                }
            }
            .background(Color.axSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.axBorder, lineWidth: 1))
        }
    }

    private func domainRow(_ domain: TrainingDomain) -> some View {
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

            // Stepper controls
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
                    let total = localFrequency.totalTrainingDays
                    if total < 6 { localFrequency.setDays(current + 1, for: domain) }
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

    // MARK: - Summary pill

    private var summary: some View {
        let n = localFrequency.totalTrainingDays
        let r = localFrequency.restDaysPerWeek

        return HStack(spacing: 16) {
            summaryChip("\(n)", label: n == 1 ? "training day" : "training days",
                        color: n > 0 ? .axGreen : .axTertiary)
            summaryChip("\(r)", label: r == 1 ? "rest day" : "rest days",
                        color: r >= 1 ? .axBlue : .axRed)
        }
        .frame(maxWidth: .infinity)
    }

    private func summaryChip(_ value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.25), value: value)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.axSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.2), lineWidth: 1))
    }

    // MARK: - Week preview

    private var weekPreview: some View {
        let plan = PlanEngine.generatePlans(
            weeks: 1,
            frequency: localFrequency,
            muscleGroupSplit: store.muscleGroupSplit
        ).first

        return VStack(alignment: .leading, spacing: 14) {
            sectionLabel("WEEK PREVIEW")

            HStack(spacing: 0) {
                ForEach(plan?.days ?? []) { day in
                    VStack(spacing: 6) {
                        Text(day.weekdayShort.prefix(1).uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.axTertiary)

                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(day.isRest
                                      ? Color.white.opacity(0.04)
                                      : (day.session?.domain.color ?? .axAccent).opacity(0.18))
                                .frame(height: 44)

                            if day.isRest {
                                Text("R")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.axTertiary)
                            } else if let domain = day.session?.domain {
                                Image(systemName: domain.icon)
                                    .font(.system(size: 14))
                                    .foregroundStyle(domain.color)
                            }
                        }

                        Text(day.session?.intensityLabel.prefix(3).uppercased() ?? "")
                            .font(.system(size: 8))
                            .foregroundStyle(.axTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .animation(.spring(duration: 0.35), value: localFrequency)
        }
    }

    // MARK: - Overload warning

    private var overloadWarning: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.axRed)
                .font(.subheadline)
                .padding(.top, 1)
            Text("Six sessions per week leaves only one rest day. This is manageable for well-trained athletes, but insufficient recovery significantly increases injury risk. At least one full rest day is required — the plan will enforce this automatically.")
                .font(.caption)
                .foregroundStyle(.axRed)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color.axRed.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.axRed.opacity(0.2), lineWidth: 1))
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.axTertiary)
            .tracking(2)
    }
}

#Preview {
    NavigationStack {
        TrainingFrequencyView()
            .environment(AthleteStore())
    }
}
