import SwiftUI

struct DashboardView: View {
    @Environment(AthleteStore.self) private var store
    @State private var showSwitcher = false

    // Resolved session — override takes priority over engine recommendation
    private var activeDomain:   TrainingDomain { store.sessionOverride?.domain       ?? store.readiness.suggestedDomain }
    private var activeTitle:    String         { store.sessionOverride?.title         ?? store.readiness.suggestedSessionTitle }
    private var activeDuration: Int            { store.sessionOverride?.duration      ?? store.readiness.suggestedDuration }
    private var activeLabel:    String         { store.sessionOverride?.intensityLabel ?? store.readiness.suggestedIntensityLabel }
    private var activeDesc:     String         { store.sessionOverride?.intensityDescription ?? store.readiness.suggestedIntensityDescription }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                headerSection
                readinessSection
                insightsSection
                sessionSection
                debugToggle
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 48)
        }
        .background(Color.axBackground.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showSwitcher) {
            ActivitySwitcherView()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(greeting)
                    .font(.subheadline)
                    .foregroundStyle(.axSecondary)
                Text(store.athleteName)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(weekdayString)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.axTertiary)
                    .tracking(1.5)
                Text(dateString)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.axSecondary)
            }
        }
    }

    // MARK: - Readiness

    private var readinessSection: some View {
        VStack(spacing: 22) {
            ReadinessRingView(score: store.readiness.score, status: store.readiness.status)
                .frame(width: 190, height: 190)
                .frame(maxWidth: .infinity)

            Text(store.readiness.status.verdict)
                .font(.title.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(store.readiness.explanation)
                .font(.subheadline)
                .foregroundStyle(.axSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)

            coachingNoteView
        }
        .padding(24)
        .background(Color.axSurface)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.axBorder, lineWidth: 1))
    }

    private var coachingNoteView: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "brain.head.profile")
                .font(.subheadline)
                .foregroundStyle(.axAccent)
                .padding(.top, 1)
            Text(store.readiness.coachingNote)
                .font(.subheadline.italic())
                .foregroundStyle(.axAccent)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.axAccent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.axAccent.opacity(0.2), lineWidth: 1))
    }

    // MARK: - Key signals

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("KEY SIGNALS")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(store.readiness.keyInsights) { insight in
                        MetricInsightCard(insight: insight)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    // MARK: - Session card

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionHeader("TODAY'S SESSION")
                Spacer()
                // "Override active" badge
                if store.sessionOverride != nil {
                    HStack(spacing: 4) {
                        Circle().fill(Color.axAccent).frame(width: 6, height: 6)
                        Text("Custom")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.axAccent)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                // Domain + title row
                HStack(spacing: 12) {
                    Image(systemName: activeDomain.icon)
                        .font(.title3)
                        .foregroundStyle(activeDomain.color)
                        .frame(width: 46, height: 46)
                        .background(activeDomain.color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 11))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(activeDomain.rawValue.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.axTertiary)
                            .tracking(1.2)
                        Text(activeTitle)
                            .font(.headline)
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(activeDuration) min")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(activeLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(.axSecondary)
                    }
                }

                Text(activeDesc)
                    .font(.subheadline)
                    .foregroundStyle(.axSecondary)

                // Strength exercises list
                if let strength = store.sessionOverride?.strengthSession {
                    strengthExerciseList(strength)
                }

                Rectangle().fill(Color.axBorder).frame(height: 1)

                // Score pills (for non-override or matching domain)
                if store.sessionOverride == nil {
                    HStack(spacing: 8) {
                        scorePill("HRV",   store.readiness.hrvScore)
                        scorePill("Sleep", store.readiness.sleepScore)
                        scorePill("Load",  store.readiness.loadScore)
                    }
                    Rectangle().fill(Color.axBorder).frame(height: 1)
                }

                // Action row
                HStack(spacing: 10) {
                    Button {
                        // start session
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                            Text("Start Session")
                        }
                        .font(.headline)
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(activeDomain.color)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    // Switch / Reset button
                    if store.sessionOverride != nil {
                        Button {
                            store.clearSessionOverride()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.subheadline.bold())
                                .foregroundStyle(.axSecondary)
                                .frame(width: 50, height: 50)
                                .background(Color.axSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.axBorder, lineWidth: 1))
                        }
                    } else {
                        Button {
                            showSwitcher = true
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.system(size: 12, weight: .bold))
                                Text("Switch")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(.axSecondary)
                            .frame(width: 100, height: 50)
                            .background(Color.axSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.axBorder, lineWidth: 1))
                        }
                    }
                }
            }
            .padding(20)
            .background(Color.axSurface)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.axBorder, lineWidth: 1))
        }
    }

    // Inline strength exercises preview
    private func strengthExerciseList(_ session: StrengthSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Muscle group chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(session.muscleGroups) { group in
                        HStack(spacing: 4) {
                            Circle().fill(group.color).frame(width: 5, height: 5)
                            Text(group.rawValue)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(group.color)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(group.color.opacity(0.08))
                        .clipShape(Capsule())
                    }
                }
            }

            Rectangle().fill(Color.axBorder).frame(height: 1)

            // Exercises
            ForEach(session.exercises) { ex in
                HStack {
                    Circle().fill(ex.muscleGroup.color).frame(width: 5, height: 5)
                    Text(ex.name)
                        .font(.subheadline)
                        .foregroundStyle(.axPrimary)
                    Spacer()
                    Text(ex.setDisplay)
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.axSecondary)
                    Text("· \(ex.rest)")
                        .font(.system(size: 11))
                        .foregroundStyle(.axTertiary)
                }
            }

            // Warnings
            ForEach(session.recoveryWarnings, id: \.self) { warning in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.axRed)
                        .padding(.top, 2)
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.axRed)
                        .lineSpacing(2)
                }
            }
        }
    }

    // MARK: - Debug

    private var debugToggle: some View {
        @Bindable var bindable = store
        return Toggle("Simulate fatigue", isOn: $bindable.useFatiguedScenario)
            .font(.caption)
            .foregroundStyle(.axTertiary)
            .tint(.axRed)
            .padding(.horizontal, 4)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func scorePill(_ label: String, _ score: Int) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.axSecondary)
            Text("\(score)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.axTertiary)
            .tracking(2)
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 12 { return "Good morning," }
        if h < 17 { return "Good afternoon," }
        return "Good evening,"
    }

    private var weekdayString: String {
        let f = DateFormatter(); f.dateFormat = "EEEE"
        return f.string(from: Date()).uppercased()
    }

    private var dateString: String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: Date())
    }
}

#Preview {
    DashboardView()
        .environment(AthleteStore())
}
