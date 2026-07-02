import SwiftUI

/// Settings → Plan (Plan §5b). Manages enrolled sports, their per-sport config
/// (weekday grid + sport-specific thresholds), and a read-only frequency summary.
/// NOTE: named TrainingPlanView (not PlanView) to avoid colliding with the Plan tab.
struct TrainingPlanView: View {
    @Environment(AthleteStore.self) private var store
    @State private var showEnrollSheet = false
    @State private var sportToRemove: TrainingDomain? = nil
    @State private var enrolledSport: TrainingDomain? = nil   // drives regen prompt

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if store.pendingPlanChanges { updatePlanBar }
                enrolledSportsSection
                frequencySummary
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color.axBackground)
        .navigationTitle("Plan")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .scrollIndicators(.hidden)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showEnrollSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showEnrollSheet) {
            EnrollSportSheet { sport in enrolledSport = sport }
        }
        .confirmationDialog(
            "Remove \(sportToRemove?.rawValue ?? "sport")?",
            isPresented: Binding(get: { sportToRemove != nil }, set: { if !$0 { sportToRemove = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let sport = sportToRemove { remove(sport) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This sport and its scheduled days will be removed from your plan.")
        }
        .confirmationDialog(
            "\(enrolledSport?.rawValue ?? "Sport") added",
            isPresented: Binding(get: { enrolledSport != nil }, set: { if !$0 { enrolledSport = nil } }),
            titleVisibility: .visible
        ) {
            Button("Got it") { enrolledSport = nil }
        } message: {
            Text("Set its training days below, then tap Update plan to regenerate your plan with the AI coach.")
        }
    }

    // MARK: - Update plan bar (staged changes)

    private var updatePlanBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.axAccent)
                Text("You have unsaved plan changes")
                    .font(.axDisplay(14, .bold))
                    .foregroundStyle(.axPrimary)
                Spacer()
            }
            Text("Generate a new two-week plan with your AI coach, tailored to your schedule, recent training, and recovery.")
                .font(.axDisplay(12))
                .foregroundStyle(.axSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await store.applyPlanChanges() }
            } label: {
                Text("Update plan")
                    .font(.axDisplay(14, .bold))
                    .foregroundStyle(Color.axBackground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.axAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .background(Color.axAccentWash)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.axAccentBorder, lineWidth: 1))
    }

    // MARK: - Enrolled sports

    private var enrolledSportsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("ENROLLED SPORTS")

            if store.enabledDomains.isEmpty {
                Text("No sports yet. Tap + to add one.")
                    .font(.axDisplay(13.5))
                    .foregroundStyle(.axSecondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.axSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.axBorder, lineWidth: 1))
            } else {
                VStack(spacing: 12) {
                    ForEach(store.enabledDomains) { domain in
                        SportConfigBlock(domain: domain) { sportToRemove = domain }
                    }
                }
            }
        }
    }

    // MARK: - Frequency summary

    private var frequencySummary: some View {
        let freq = store.trainingFrequency
        let sessions = freq.totalSessions
        let sports = freq.schedules.count
        return VStack(alignment: .leading, spacing: 12) {
            SectionLabel("TRAINING FREQUENCY")
            AxCard(radius: 16, padding: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(sessions) \(sessions == 1 ? "session" : "sessions")/week across \(sports) \(sports == 1 ? "sport" : "sports")")
                        .font(.axDisplay(14, .semibold))
                        .foregroundStyle(.axPrimary)
                    if freq.isOverloaded {
                        Label("Training 7 days a week leaves no rest — consider a recovery day.", systemImage: "exclamationmark.triangle.fill")
                            .font(.axDisplay(12))
                            .foregroundStyle(.axRed)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Actions

    private func remove(_ domain: TrainingDomain) {
        store.enabledDomains.removeAll { $0 == domain }
        store.trainingFrequency.setDays([], for: domain)   // drops its schedule + regen via didSet
        sportToRemove = nil
    }
}

// MARK: - Per-sport config block

/// One expandable block per enrolled sport: shared weekday grid + a
/// `switch domain` for sport-specific config. Single view by design (no
/// per-sport protocol) per project guidelines.
private struct SportConfigBlock: View {
    @Environment(AthleteStore.self) private var store
    let domain: TrainingDomain
    let onRemove: () -> Void

    @State private var expanded = false
    @State private var showScheduleRegen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if expanded {
                VStack(alignment: .leading, spacing: 16) {
                    weekdaySection
                    sportSpecificConfig
                }
                .padding(16)
                .padding(.top, 4)
            }
        }
        .background(Color.axSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.axBorder, lineWidth: 1))
        .animation(.spring(duration: 0.3), value: expanded)
        .confirmationDialog(
            "Schedule changed",
            isPresented: $showScheduleRegen,
            titleVisibility: .visible
        ) {
            Button("Update plan") {
                showScheduleRegen = false
                Task { await store.applyPlanChanges() }
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Your schedule changed — generate a new two-week plan with the AI coach?")
        }
    }

    private var header: some View {
        Button {
            expanded.toggle()
        } label: {
            HStack(spacing: 14) {
                IconTile(systemName: domain.icon, color: domain.color, size: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(domain.rawValue)
                        .font(.axDisplay(15, .semibold))
                        .foregroundStyle(.axPrimary)
                    Text(daysSummary.uppercased())
                        .font(.axMono(10))
                        .tracking(0.6)
                        .foregroundStyle(.axSecondary)
                }

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.axTertiary)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .padding(16)
        }
    }

    private var daysSummary: String {
        let n = store.trainingFrequency.days(for: domain)
        return n == 0 ? "No days set" : "\(n) \(n == 1 ? "day" : "days")/week"
    }

    private var weekdaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                configLabel("TRAINING DAYS")
                Spacer()
                Button(role: .destructive, action: onRemove) {
                    Text("REMOVE")
                        .font(.axMono(10, .semibold))
                        .tracking(1)
                        .foregroundStyle(.axRed)
                }
            }
            WeekdayGridView(domain: domain)
            Button {
                showScheduleRegen = true
            } label: {
                Text("↻ REBUILD PLAN AFTER CHANGING DAYS")
                    .font(.axMono(9, .semibold))
                    .tracking(1)
                    .foregroundStyle(.axAccent)
            }
        }
    }

    @ViewBuilder
    private var sportSpecificConfig: some View {
        switch domain {
        case .strength:
            VStack(alignment: .leading, spacing: 10) {
                configLabel("MUSCLE GROUP SPLIT")
                MuscleSplitEditor()
            }
        case .cycling:
            CyclingConfig()
        case .running:
            RunningConfig()
        case .swimming:
            SwimmingConfig()
        case .triathlon, .mobility, .recovery:
            EmptyView()   // weekday grid only
        }
    }
}

// MARK: - Cycling config (HR vs Power + thresholds)

private struct CyclingConfig: View {
    @Environment(AthleteStore.self) private var store

    var body: some View {
        @Bindable var bindable = store
        return VStack(alignment: .leading, spacing: 12) {
            configLabel("WORKOUT TARGET")
            AxSegmented(
                options: [("hr", "Heart rate"), ("power", "Power")],
                selection: $bindable.cyclingTarget
            )

            if store.cyclingTarget == "power" {
                IntThresholdField(label: "FTP (watts)", placeholder: "e.g. 250",
                                  value: { store.thresholds.ftpWatts },
                                  set: { store.thresholds.ftpWatts = $0 })
            } else {
                IntThresholdField(label: "Threshold HR (bpm)", placeholder: "e.g. 165",
                                  value: { store.thresholds.thresholdHr },
                                  set: { store.thresholds.thresholdHr = $0 })
                IntThresholdField(label: "Max HR (bpm)", placeholder: "e.g. 190",
                                  value: { store.thresholds.maxHr },
                                  set: { store.thresholds.maxHr = $0 })
            }

            configLabel("GOAL")
            AxSegmented(
                options: [("none", "None"),
                          (GoalType.powerHold.rawValue, "Power hold"),
                          (GoalType.distanceAvgSpeed.rawValue, "Dist @ speed")],
                selection: goalKindBinding
            )
            if let target = store.sportTargets[.cycling] {
                if target.goalType == .powerHold {
                    AxSegmented(
                        options: [(1, "Z1"), (2, "Z2"), (3, "Z3"), (4, "Z4"), (5, "Z5")],
                        selection: Binding(
                            get: { store.sportTargets[.cycling]?.zone ?? 4 },
                            set: { store.sportTargets[.cycling]?.zone = $0 }
                        )
                    )
                    IntThresholdField(label: "Hold duration (min)", placeholder: "e.g. 20",
                                      value: { store.sportTargets[.cycling]?.holdMinutes },
                                      set: { store.sportTargets[.cycling]?.holdMinutes = $0 })
                } else {
                    DecimalThresholdField(label: "Distance (km)", placeholder: "e.g. 100",
                                          value: { store.sportTargets[.cycling]?.distanceKm },
                                          set: { store.sportTargets[.cycling]?.distanceKm = $0 })
                    DecimalThresholdField(label: "Avg speed (km/h)", placeholder: "e.g. 30",
                                          value: { store.sportTargets[.cycling]?.avgSpeedKmh },
                                          set: { store.sportTargets[.cycling]?.avgSpeedKmh = $0 })
                }
                TargetDateRow(date: Binding(
                    get: { store.sportTargets[.cycling]?.targetDate ?? defaultTargetDate() },
                    set: { store.sportTargets[.cycling]?.targetDate = $0 }
                ))
            }
        }
    }

    /// "None" clears the goal; picking a kind creates a fresh target (keeping the
    /// date when switching kinds). Zone defaults to Z4 for power holds.
    private var goalKindBinding: Binding<String> {
        Binding(
            get: { store.sportTargets[.cycling]?.goalType.rawValue ?? "none" },
            set: { kind in
                guard let goal = GoalType(rawValue: kind) else {
                    store.sportTargets[.cycling] = nil
                    return
                }
                guard store.sportTargets[.cycling]?.goalType != goal else { return }
                let date = store.sportTargets[.cycling]?.targetDate ?? defaultTargetDate()
                var target = SportTarget(goalType: goal, targetDate: date)
                if goal == .powerHold { target.zone = 4 }
                store.sportTargets[.cycling] = target
            }
        )
    }
}

// MARK: - Running config (pace unit + threshold pace)

private struct RunningConfig: View {
    @Environment(AthleteStore.self) private var store

    var body: some View {
        @Bindable var bindable = store
        return VStack(alignment: .leading, spacing: 12) {
            configLabel("PACE")
            AxSegmented(
                options: [(PaceUnit.km, "min/km"), (PaceUnit.mile, "min/mile")],
                selection: $bindable.thresholds.paceUnit
            )

            PaceThresholdField(
                label: "Threshold pace (mm:ss / \(store.thresholds.paceUnit == .km ? "km" : "mile"))",
                value: { store.thresholds.runThresholdPaceSecPerKm },
                set: { store.thresholds.runThresholdPaceSecPerKm = $0 })

            configLabel("GOAL")
            AxSegmented(
                options: [("none", "None"), (GoalType.raceTime.rawValue, "Race time")],
                selection: goalKindBinding
            )
            if store.sportTargets[.running] != nil {
                DecimalThresholdField(label: "Race distance (km)", placeholder: "e.g. 10",
                                      value: { store.sportTargets[.running]?.distanceKm },
                                      set: { store.sportTargets[.running]?.distanceKm = $0 })
                DurationField(label: "Finish time (h:mm:ss)",
                              value: { store.sportTargets[.running]?.finishTimeSec },
                              set: { store.sportTargets[.running]?.finishTimeSec = $0 })
                TargetDateRow(date: Binding(
                    get: { store.sportTargets[.running]?.targetDate ?? defaultTargetDate() },
                    set: { store.sportTargets[.running]?.targetDate = $0 }
                ))
            }
        }
    }

    /// "None" clears the goal; "Race time" creates a fresh target.
    private var goalKindBinding: Binding<String> {
        Binding(
            get: { store.sportTargets[.running]?.goalType.rawValue ?? "none" },
            set: { kind in
                guard GoalType(rawValue: kind) == .raceTime else {
                    store.sportTargets[.running] = nil
                    return
                }
                guard store.sportTargets[.running] == nil else { return }
                store.sportTargets[.running] = SportTarget(goalType: .raceTime, targetDate: defaultTargetDate())
            }
        )
    }
}

// MARK: - Swimming config (pool unit + threshold pace per 100m)

private struct SwimmingConfig: View {
    @Environment(AthleteStore.self) private var store

    var body: some View {
        @Bindable var bindable = store
        return VStack(alignment: .leading, spacing: 12) {
            configLabel("POOL")
            AxSegmented(
                options: [(PoolUnit.pool25m, "25 m"), (PoolUnit.pool50m, "50 m"), (PoolUnit.openWater, "Open water")],
                selection: $bindable.thresholds.poolUnit
            )

            PaceThresholdField(
                label: "Threshold pace (mm:ss / 100m)",
                value: { store.thresholds.swimThresholdPaceSecPer100m },
                set: { store.thresholds.swimThresholdPaceSecPer100m = $0 })
        }
    }
}

// MARK: - Threshold input fields (local @State; commit on submit/blur)

/// Integer threshold field. Binds to LOCAL state and writes back to the store
/// only onSubmit / when focus is lost, so the store doesn't PATCH per keystroke.
private struct IntThresholdField: View {
    let label: String
    let placeholder: String
    let value: () -> Int?
    let set: (Int?) -> Void

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text(label)
                .font(.axDisplay(13.5))
                .foregroundStyle(.axSecondary)
            Spacer()
            TextField(placeholder, text: $text)
                .multilineTextAlignment(.trailing)
                .font(.axMono(13, .semibold))
                .foregroundStyle(.axPrimary)
                .focused($focused)
#if os(iOS)
                .keyboardType(.numberPad)
#endif
                .frame(maxWidth: 120)
                .onSubmit(commit)
        }
        .padding(.vertical, 4)
        .onAppear { text = value().map(String.init) ?? "" }
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        set(trimmed.isEmpty ? nil : Int(trimmed))
    }
}

/// Pace field: user enters mm:ss, stored as Int seconds. Empty when nil.
private struct PaceThresholdField: View {
    let label: String
    let value: () -> Int?
    let set: (Int?) -> Void

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text(label)
                .font(.axDisplay(13.5))
                .foregroundStyle(.axSecondary)
            Spacer()
            TextField("mm:ss", text: $text)
                .multilineTextAlignment(.trailing)
                .font(.axMono(13, .semibold))
                .foregroundStyle(.axPrimary)
                .focused($focused)
                .frame(maxWidth: 90)
                .onSubmit(commit)
        }
        .padding(.vertical, 4)
        .onAppear { text = Self.format(value()) }
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
    }

    private func commit() {
        let secs = Self.parse(text)
        set(secs)
        text = Self.format(secs)   // normalise display
    }

    static func parse(_ s: String) -> Int? {
        let parts = s.split(separator: ":")
        guard parts.count == 2,
              let m = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let sec = Int(parts[1].trimmingCharacters(in: .whitespaces)),
              (0..<60).contains(sec) else { return nil }
        return m * 60 + sec
    }

    static func format(_ secs: Int?) -> String {
        guard let secs else { return "" }
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }
}

/// Decimal threshold field (same commit-on-blur behaviour as IntThresholdField).
private struct DecimalThresholdField: View {
    let label: String
    let placeholder: String
    let value: () -> Double?
    let set: (Double?) -> Void

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text(label)
                .font(.axDisplay(13.5))
                .foregroundStyle(.axSecondary)
            Spacer()
            TextField(placeholder, text: $text)
                .multilineTextAlignment(.trailing)
                .font(.axMono(13, .semibold))
                .foregroundStyle(.axPrimary)
                .focused($focused)
#if os(iOS)
                .keyboardType(.decimalPad)
#endif
                .frame(maxWidth: 120)
                .onSubmit(commit)
        }
        .padding(.vertical, 4)
        .onAppear { text = value().map { String(format: "%g", $0) } ?? "" }
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        set(trimmed.isEmpty ? nil : Double(trimmed))
    }
}

/// Duration field: user enters h:mm:ss or mm:ss, stored as Int seconds. Race
/// finish times can exceed an hour, which the mm:ss PaceThresholdField can't hold.
private struct DurationField: View {
    let label: String
    let value: () -> Int?
    let set: (Int?) -> Void

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text(label)
                .font(.axDisplay(13.5))
                .foregroundStyle(.axSecondary)
            Spacer()
            TextField("h:mm:ss", text: $text)
                .multilineTextAlignment(.trailing)
                .font(.axMono(13, .semibold))
                .foregroundStyle(.axPrimary)
                .focused($focused)
                .frame(maxWidth: 100)
                .onSubmit(commit)
        }
        .padding(.vertical, 4)
        .onAppear { text = Self.format(value()) }
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
    }

    private func commit() {
        let secs = Self.parse(text)
        set(secs)
        text = Self.format(secs)   // normalise display
    }

    static func parse(_ s: String) -> Int? {
        let parts = s.split(separator: ":").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.allSatisfy({ $0 != nil }) else { return nil }
        let nums = parts.compactMap { $0 }
        switch nums.count {
        case 2 where (0..<60).contains(nums[1]):
            return nums[0] * 60 + nums[1]
        case 3 where (0..<60).contains(nums[1]) && (0..<60).contains(nums[2]):
            return nums[0] * 3600 + nums[1] * 60 + nums[2]
        default:
            return nil
        }
    }

    static func format(_ secs: Int?) -> String {
        guard let secs else { return "" }
        if secs >= 3600 {
            return String(format: "%d:%02d:%02d", secs / 3600, (secs % 3600) / 60, secs % 60)
        }
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }
}

/// Compact goal target-date row, styled like the threshold rows.
private struct TargetDateRow: View {
    let date: Binding<Date>

    var body: some View {
        HStack {
            Text("Target date")
                .font(.axDisplay(13.5))
                .foregroundStyle(.axSecondary)
            Spacer()
            DatePicker("", selection: date, in: Date()..., displayedComponents: .date)
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

/// Fresh goals default to ~12 weeks out — a sane training-block horizon.
private func defaultTargetDate() -> Date {
    Calendar.current.date(byAdding: .weekOfYear, value: 12, to: Date()) ?? Date()
}

// MARK: - Shared small label

private func configLabel(_ text: String) -> some View {
    Text(text).axSectionLabel()
}

#Preview {
    NavigationStack {
        TrainingPlanView()
            .environment(AthleteStore())
    }
}
