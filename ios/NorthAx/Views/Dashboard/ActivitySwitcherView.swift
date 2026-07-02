import SwiftUI

struct ActivitySwitcherView: View {
    @Environment(AthleteStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let readiness = store.readiness {
                    content(readiness)
                } else {
                    ContentUnavailableView(
                        "No data yet",
                        systemImage: "antenna.radiowaves.left.and.right",
                        description: Text("Connect a data source to get session suggestions matched to your readiness.")
                    )
                }
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

    private func content(_ readiness: DailyReadiness) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                subtitle(readiness)

                // Standard activity alternatives
                VStack(spacing: 12) {
                    ForEach(TrainingDomain.allCases.filter { $0 != .recovery }) { domain in
                        if domain == .strength {
                            strengthOption(readiness)
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
    }

    // MARK: - Subtitle

    private func subtitle(_ readiness: DailyReadiness) -> some View {
        Text("What do you feel like today? Each option targets the same training load (~\(Int(store.prescribedLoad.rounded()))) as your planned session — duration is scaled to the sport and your readiness of \(readiness.score)/100.")
            .font(.axDisplay(13.5))
            .foregroundStyle(.axSecondary)
            .lineSpacing(4)
    }

    // MARK: - Standard domain option

    private func standardOption(for domain: TrainingDomain) -> some View {
        let session = store.switchSuggestion(for: domain)
        let load = Int(store.sessionLoad(durationMin: session.duration, intensity: session.intensityLabel).rounded())

        return Button {
            store.switchSession(to: domain, strengthSession: nil)
            dismiss()
        } label: {
            AxCard(radius: 16, padding: 16) {
                HStack(spacing: 14) {
                    IconTile(systemName: domain.icon, color: domain.color, size: 46)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(domain.rawValue)
                                .font(.axDisplay(16, .bold))
                                .foregroundStyle(.axPrimary)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("\(session.duration) MIN")
                                    .font(.axMono(11, .semibold))
                                    .foregroundStyle(.axSecondary)
                                Text("~\(load) LOAD")
                                    .font(.axMono(9))
                                    .foregroundStyle(.axTertiary)
                            }
                        }
                        Text(session.intensityDescription)
                            .font(.axDisplay(11.5))
                            .foregroundStyle(.axTertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    // MARK: - Strength option (expanded, shows muscle groups)

    private func strengthOption(_ readiness: DailyReadiness) -> some View {
        let weekday   = Calendar.current.component(.weekday, from: Date())
        let daySplit  = store.muscleGroupSplit.split(forCalendarWeekday: weekday)
        let groups    = daySplit.isRestDay ? MuscleGroup.allCases.prefix(3).map { $0 } : daySplit.muscleGroups
        let session   = StrengthEngine.generateSession(
            muscleGroups: groups,
            readiness: readiness,
            recentActivities: store.intervals.syncedActivities
        )

        return Button {
            // Instant: engine-built session (parity with the server). Then refine
            // with the backend's AI rationale/recovery warnings when available.
            store.switchSession(to: .strength, strengthSession: session)
            dismiss()
            Task {
                if let enriched = await store.generateStrengthSession(for: groups) {
                    store.switchSession(to: .strength, strengthSession: enriched)
                }
            }
        } label: {
            AxCard(radius: 16, padding: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    // Header row
                    HStack(spacing: 14) {
                        IconTile(systemName: TrainingDomain.strength.icon, color: TrainingDomain.strength.color, size: 46)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(session.title)
                                    .font(.axDisplay(16, .bold))
                                    .foregroundStyle(.axPrimary)
                                Spacer()
                                Text("\(session.duration) MIN")
                                    .font(.axMono(11, .semibold))
                                    .foregroundStyle(.axSecondary)
                            }
                            Text(session.intensityLabel + " · From your weekly split")
                                .font(.axDisplay(11.5))
                                .foregroundStyle(.axTertiary)
                        }
                    }

                    // Muscle group chips
                    if !groups.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(groups) { group in
                                    AxPill(text: group.rawValue, color: group.color)
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
                                    .font(.axDisplay(13.5, .medium))
                                    .foregroundStyle(.axPrimary)
                                Spacer()
                                Text(ex.setDisplay)
                                    .font(.axMono(11, .semibold))
                                    .foregroundStyle(.axSecondary)
                            }
                        }
                        if session.exercises.count > 3 {
                            Text("+ \(session.exercises.count - 3) MORE EXERCISES")
                                .font(.axMono(10))
                                .tracking(0.8)
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
                                .font(.axDisplay(12))
                                .foregroundStyle(.axRed)
                                .lineLimit(2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

}

#Preview {
    ActivitySwitcherView()
        .environment(AthleteStore())
}
