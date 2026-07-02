import SwiftUI

/// Settings → Plan → Goals. Edits per-sport goal targets against a LOCAL draft:
/// Save writes the draft to the store (staging a plan change, applied via the
/// Plan page's "Update plan" bar); Back asks to discard unsaved edits.
struct GoalsView: View {
    @Environment(AthleteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: [TrainingDomain: SportTarget]
    @State private var showDiscardConfirm = false

    init(initial: [TrainingDomain: SportTarget]) {
        _draft = State(initialValue: initial)
    }

    private var isDirty: Bool { draft != store.sportTargets }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if store.enabledDomains.contains(.running) { runningSection }
                if store.enabledDomains.contains(.cycling) { cyclingSection }
                if !store.enabledDomains.contains(.running), !store.enabledDomains.contains(.cycling) {
                    emptyHint
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color.axBackground)
        .navigationTitle("Goals")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)   // Back must go through the discard check
#endif
        .scrollIndicators(.hidden)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    if isDirty { showDiscardConfirm = true } else { dismiss() }
                } label: {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    store.sportTargets = draft   // stages pendingPlanChanges via didSet
                    dismiss()
                }
                .disabled(!isDirty)
            }
        }
        .confirmationDialog(
            "Discard changes?",
            isPresented: $showDiscardConfirm,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your goal edits haven't been saved and will be lost.")
        }
    }

    // MARK: - Running (race time)

    private var runningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("RUNNING")
            AxCard(radius: 16, padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    AxSegmented(
                        options: [("none", "None"), (GoalType.raceTime.rawValue, "Race time")],
                        selection: runningKindBinding
                    )
                    if draft[.running] != nil {
                        DecimalGoalField(label: "Race distance (km)", placeholder: "e.g. 10",
                                         value: { draft[.running]?.distanceKm },
                                         set: { draft[.running]?.distanceKm = $0 })
                        DurationField(label: "Finish time (h:mm:ss)",
                                      value: { draft[.running]?.finishTimeSec },
                                      set: { draft[.running]?.finishTimeSec = $0 })
                        TargetDateRow(date: Binding(
                            get: { draft[.running]?.targetDate ?? defaultTargetDate() },
                            set: { draft[.running]?.targetDate = $0 }
                        ))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// "None" clears the goal; "Race time" creates a fresh target.
    private var runningKindBinding: Binding<String> {
        Binding(
            get: { draft[.running]?.goalType.rawValue ?? "none" },
            set: { kind in
                guard GoalType(rawValue: kind) == .raceTime else {
                    draft[.running] = nil
                    return
                }
                guard draft[.running] == nil else { return }
                draft[.running] = SportTarget(goalType: .raceTime, targetDate: defaultTargetDate())
            }
        )
    }

    // MARK: - Cycling (power hold / distance @ speed)

    private var cyclingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("CYCLING")
            AxCard(radius: 16, padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    AxSegmented(
                        options: [("none", "None"),
                                  (GoalType.powerHold.rawValue, "Power hold"),
                                  (GoalType.distanceAvgSpeed.rawValue, "Dist @ speed")],
                        selection: cyclingKindBinding
                    )
                    if let target = draft[.cycling] {
                        if target.goalType == .powerHold {
                            AxSegmented(
                                options: [(1, "Z1"), (2, "Z2"), (3, "Z3"), (4, "Z4"), (5, "Z5")],
                                selection: Binding(
                                    get: { draft[.cycling]?.zone ?? 4 },
                                    set: { draft[.cycling]?.zone = $0 }
                                )
                            )
                            IntGoalField(label: "Hold duration (min)", placeholder: "e.g. 20",
                                         value: { draft[.cycling]?.holdMinutes },
                                         set: { draft[.cycling]?.holdMinutes = $0 })
                        } else {
                            DecimalGoalField(label: "Distance (km)", placeholder: "e.g. 100",
                                             value: { draft[.cycling]?.distanceKm },
                                             set: { draft[.cycling]?.distanceKm = $0 })
                            DecimalGoalField(label: "Avg speed (km/h)", placeholder: "e.g. 30",
                                             value: { draft[.cycling]?.avgSpeedKmh },
                                             set: { draft[.cycling]?.avgSpeedKmh = $0 })
                        }
                        TargetDateRow(date: Binding(
                            get: { draft[.cycling]?.targetDate ?? defaultTargetDate() },
                            set: { draft[.cycling]?.targetDate = $0 }
                        ))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// "None" clears the goal; picking a kind creates a fresh target (keeping the
    /// date when switching kinds). Zone defaults to Z4 for power holds.
    private var cyclingKindBinding: Binding<String> {
        Binding(
            get: { draft[.cycling]?.goalType.rawValue ?? "none" },
            set: { kind in
                guard let goal = GoalType(rawValue: kind) else {
                    draft[.cycling] = nil
                    return
                }
                guard draft[.cycling]?.goalType != goal else { return }
                let date = draft[.cycling]?.targetDate ?? defaultTargetDate()
                var target = SportTarget(goalType: goal, targetDate: date)
                if goal == .powerHold { target.zone = 4 }
                draft[.cycling] = target
            }
        )
    }

    // MARK: - Empty state

    private var emptyHint: some View {
        Text("Enroll Running or Cycling on the Plan page to set a goal.")
            .font(.axDisplay(13.5))
            .foregroundStyle(.axSecondary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.axSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.axBorder, lineWidth: 1))
    }
}

// MARK: - Goal input fields (local @State; commit on submit/blur)

/// Integer goal field — same commit-on-blur behaviour as the Plan page's
/// IntThresholdField (which stays private to TrainingPlanView).
private struct IntGoalField: View {
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

/// Decimal goal field (same commit-on-blur behaviour).
private struct DecimalGoalField: View {
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
/// finish times can exceed an hour, which a mm:ss pace field can't hold.
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

#Preview {
    NavigationStack {
        GoalsView(initial: [:])
            .environment(AthleteStore())
    }
}
