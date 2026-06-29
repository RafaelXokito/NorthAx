import SwiftUI

struct ActivitySwitcherView: View {
    @Environment(AthleteStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    subtitle

                    // Standard activity alternatives
                    VStack(spacing: 12) {
                        ForEach(TrainingDomain.allCases.filter { $0 != .recovery }) { domain in
                            if domain == .strength {
                                strengthOption
                            } else {
                                standardOption(for: domain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(Color.axBackground.ignoresSafeArea())
            .navigationTitle("Switch Activity")
            .scrollIndicators(.hidden)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.axSecondary)
                }
            }
        }
    }

    // MARK: - Subtitle

    private var subtitle: some View {
        Text("What do you feel like today? The app will adjust intensity and session structure to match your current readiness of \(store.readiness.score)/100.")
            .font(.subheadline)
            .foregroundStyle(.axSecondary)
            .lineSpacing(4)
    }

    // MARK: - Standard domain option

    private func standardOption(for domain: TrainingDomain) -> some View {
        let session = standardSession(for: domain, readiness: store.readiness)

        return Button {
            store.switchSession(to: domain, strengthSession: nil)
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: domain.icon)
                    .font(.title3)
                    .foregroundStyle(domain.color)
                    .frame(width: 46, height: 46)
                    .background(domain.color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(domain.rawValue)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(session.duration) min")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.axSecondary)
                    }
                    Text(session.intensityDescription)
                        .font(.caption)
                        .foregroundStyle(.axTertiary)
                        .lineLimit(1)
                }
            }
            .padding(16)
            .background(Color.axSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.axBorder, lineWidth: 1))
        }
    }

    // MARK: - Strength option (expanded, shows muscle groups)

    private var strengthOption: some View {
        let weekday   = Calendar.current.component(.weekday, from: Date())
        let daySplit  = store.muscleGroupSplit.split(forCalendarWeekday: weekday)
        let groups    = daySplit.isRestDay ? MuscleGroup.allCases.prefix(3).map { $0 } : daySplit.muscleGroups
        let session   = StrengthEngine.generateSession(
            muscleGroups: groups,
            readiness: store.readiness,
            recentActivities: store.garmin.syncedActivities
        )

        return Button {
            store.switchSession(to: .strength, strengthSession: session)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                // Header row
                HStack(spacing: 14) {
                    Image(systemName: TrainingDomain.strength.icon)
                        .font(.title3)
                        .foregroundStyle(TrainingDomain.strength.color)
                        .frame(width: 46, height: 46)
                        .background(TrainingDomain.strength.color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 11))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(session.title)
                                .font(.headline)
                                .foregroundStyle(.white)
                            Spacer()
                            Text("\(session.duration) min")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.axSecondary)
                        }
                        Text(session.intensityLabel + " · From your weekly split")
                            .font(.caption)
                            .foregroundStyle(.axTertiary)
                    }
                }

                // Muscle group chips
                if !groups.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(groups) { group in
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(group.color)
                                        .frame(width: 6, height: 6)
                                    Text(group.rawValue)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.axPrimary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(group.color.opacity(0.10))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(group.color.opacity(0.25), lineWidth: 1))
                            }
                        }
                    }
                }

                Rectangle().fill(Color.axBorder).frame(height: 1)

                // Exercise preview (top 3)
                VStack(spacing: 8) {
                    ForEach(session.exercises.prefix(3)) { ex in
                        HStack {
                            Circle().fill(ex.muscleGroup.color).frame(width: 6, height: 6)
                            Text(ex.name)
                                .font(.subheadline)
                                .foregroundStyle(.axPrimary)
                            Spacer()
                            Text(ex.setDisplay)
                                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.axSecondary)
                        }
                    }
                    if session.exercises.count > 3 {
                        Text("+ \(session.exercises.count - 3) more exercises")
                            .font(.caption)
                            .foregroundStyle(.axTertiary)
                    }
                }

                // Recovery warnings
                if !session.recoveryWarnings.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.axRed)
                            .padding(.top, 1)
                        Text(session.recoveryWarnings[0])
                            .font(.caption)
                            .foregroundStyle(.axRed)
                            .lineLimit(2)
                    }
                }
            }
            .padding(16)
            .background(Color.axSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.axBorder, lineWidth: 1))
        }
    }

    // MARK: - Standard session generator

    private func standardSession(for domain: TrainingDomain, readiness: DailyReadiness)
        -> (duration: Int, intensityDescription: String)
    {
        switch domain {
        case .cycling:
            if readiness.score >= 80 { return (75, "Zone 3 Intervals · 70–85% FTP") }
            if readiness.score >= 60 { return (90, "Aerobic Endurance · 65–75% FTP") }
            return (45, "Recovery Ride · Zone 1–2")

        case .running:
            if readiness.score >= 80 { return (50, "Tempo Run · Comfortably hard pace") }
            if readiness.score >= 60 { return (45, "Easy Run · Zone 2") }
            return (30, "Easy Jog · Conversational pace")

        case .swimming:
            if readiness.score >= 80 { return (60, "Interval Set · 8×100m at race pace") }
            if readiness.score >= 60 { return (45, "Technique Set · Drills + aerobic") }
            return (30, "Easy Swim · Continuous aerobic")

        case .triathlon:
            return (90, "Brick · 60 min bike + 20 min run")

        case .mobility:
            return (40, "Yoga Flow · Hip flexors, hamstrings, thoracic")

        case .recovery:
            return (20, "Active Recovery · Short walk or light stretching")

        case .strength:
            return (60, "Gym Session · Based on your weekly split")
        }
    }
}

#Preview {
    ActivitySwitcherView()
        .environment(AthleteStore())
}
