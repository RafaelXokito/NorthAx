import SwiftUI

/// Live logging for a strength session — the only sport that can be "started"
/// in-app. Exercises are pre-filled from the plan; the athlete records weight ×
/// reps per set, can add/remove sets and exercises, and finishing persists a
/// `manual` activity (so the plan matcher marks the session done).
///
/// Also doubles as the after-the-fact editor for a done workout's exercise log
/// (`init(editing:)`): same set-by-set UI, no timer, saving PATCHes the activity.
struct StrengthLoggerView: View {
    let title: String
    /// When set, the view edits this activity's logged exercises instead of
    /// running a live workout.
    let editingActivity: GarminActivity?
    /// Called after a successful save so the presenting detail view can close
    /// (its `match` snapshot is stale once the activity exists / changed).
    var onSaved: () -> Void

    @Environment(AthleteStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var startedAt = Date()
    @State private var exercises: [ExerciseDraft]
    @State private var showPicker = false
    @State private var confirmDiscard = false
    @State private var saving = false
    @State private var saveFailed = false

    init(match: SessionMatch, onSaved: @escaping () -> Void) {
        title = match.session.title
        editingActivity = nil
        self.onSaved = onSaved
        _exercises = State(initialValue: (match.session.exercises ?? []).map { ExerciseDraft(suggestion: $0) })
    }

    init(editing activity: GarminActivity, onSaved: @escaping () -> Void) {
        title = activity.name
        editingActivity = activity
        self.onSaved = onSaved
        _exercises = State(initialValue: (activity.strengthExercises ?? []).map { ExerciseDraft(logged: $0) })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if editingActivity == nil { timerCard }
                    ForEach($exercises) { $draft in
                        ExerciseLogCard(draft: $draft) {
                            exercises.removeAll { $0.id == draft.id }
                        }
                    }
                    addExerciseButton
                    if saveFailed {
                        Text("Couldn't save the workout — check your connection and try again.")
                            .font(.caption).foregroundStyle(.axRed)
                    }
                    finishButton
                }
                .padding(20)
            }
            .background(Color.axBackground)
            .navigationTitle(title)
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasLoggedSets { confirmDiscard = true } else { dismiss() }
                    }
                }
            }
            .confirmationDialog(editingActivity == nil ? "Discard this workout?" : "Discard your changes?",
                                isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button(editingActivity == nil ? "Discard workout" : "Discard changes", role: .destructive) { dismiss() }
                Button(editingActivity == nil ? "Keep logging" : "Keep editing", role: .cancel) {}
            }
            .sheet(isPresented: $showPicker) {
                ExercisePickerView { name, group in
                    exercises.append(ExerciseDraft(name: name, muscleGroup: group))
                }
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Timer

    private var timerCard: some View {
        AxCard(radius: 18, padding: 16, highlighted: true) {
            HStack(spacing: 14) {
                IconTile(systemName: TrainingDomain.strength.icon, color: .axStrengthSport, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("WORKOUT IN PROGRESS")
                        .font(.axMono(10, .semibold)).tracking(1.2)
                        .foregroundStyle(.axAccent)
                    TimelineView(.periodic(from: startedAt, by: 1)) { context in
                        Text(elapsedLabel(at: context.date))
                            .font(.axMono(26, .bold))
                            .foregroundStyle(.axPrimary)
                            .monospacedDigit()
                    }
                }
                Spacer()
            }
        }
    }

    private func elapsedLabel(at now: Date) -> String {
        let s = Swift.max(0, Int(now.timeIntervalSince(startedAt)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    // MARK: - Actions

    private var addExerciseButton: some View {
        Button { showPicker = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                Text("Add exercise")
            }
            .font(.axDisplay(14, .bold))
            .foregroundStyle(.axAccent)
            .frame(maxWidth: .infinity).frame(height: 46)
            .background(Color.axAccent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    /// At least one set with reps entered somewhere — the minimum worth saving.
    private var hasLoggedSets: Bool {
        exercises.contains { $0.sets.contains { $0.repsValue != nil } }
    }

    private var finishButton: some View {
        Button {
            saving = true
            saveFailed = false
            Task {
                let logged = exercises.compactMap { $0.toLogged() }
                let ok: Bool
                if let activity = editingActivity {
                    ok = await store.updateStrengthWorkout(activityId: activity.id, exercises: logged)
                } else {
                    let duration = Swift.max(60, Int(Date().timeIntervalSince(startedAt)))
                    ok = await store.logStrengthWorkout(
                        title: title, startedAt: startedAt,
                        durationSeconds: duration, exercises: logged
                    )
                }
                saving = false
                if ok {
                    dismiss()
                    onSaved()
                } else {
                    saveFailed = true
                }
            }
        } label: {
            HStack(spacing: 6) {
                if saving { ProgressView().controlSize(.small).tint(.axBackground) }
                Image(systemName: "checkmark.circle.fill")
                Text(saving ? "Saving…" : (editingActivity == nil ? "Finish workout" : "Save changes"))
            }
            .font(.axDisplay(15, .bold))
            .foregroundStyle(Color.axBackground)
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(hasLoggedSets ? Color.axGreen : Color.axGreen.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .disabled(!hasLoggedSets || saving)
    }
}

// MARK: - Drafts (text-field-friendly working state)

private struct SetDraft: Identifiable {
    let id = UUID()
    var weightText = ""
    var repsText = ""

    var weightValue: Double? { Double(weightText.replacingOccurrences(of: ",", with: ".")) }
    var repsValue: Int? { Int(repsText).flatMap { $0 > 0 ? $0 : nil } }
}

private struct ExerciseDraft: Identifiable {
    let id = UUID()
    var name: String
    var muscleGroup: MuscleGroup
    var repsHint: String
    var sets: [SetDraft]

    init(suggestion: ExerciseSuggestion) {
        name = suggestion.name
        muscleGroup = suggestion.muscleGroup
        repsHint = suggestion.repsRange
        sets = (0..<Swift.max(1, suggestion.sets)).map { _ in SetDraft() }
    }

    init(name: String, muscleGroup: MuscleGroup) {
        self.name = name
        self.muscleGroup = muscleGroup
        repsHint = "reps"
        sets = [SetDraft(), SetDraft(), SetDraft()]
    }

    /// Prefill from an existing exercise log (edit mode).
    init(logged: LoggedExercise) {
        name = logged.name
        muscleGroup = logged.muscleGroup
        repsHint = "reps"
        sets = logged.sets.map {
            SetDraft(weightText: $0.weightKg.map(Self.weightText) ?? "",
                     repsText: String($0.reps))
        }
    }

    private static func weightText(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(w)) : String(w)
    }

    /// Only sets with reps entered count; an untouched exercise drops out.
    func toLogged() -> LoggedExercise? {
        let done = sets.compactMap { set in
            set.repsValue.map { LoggedSet(weightKg: set.weightValue, reps: $0) }
        }
        guard !done.isEmpty else { return nil }
        return LoggedExercise(name: name, muscleGroup: muscleGroup, sets: done)
    }
}

// MARK: - One exercise card

private struct ExerciseLogCard: View {
    @Binding var draft: ExerciseDraft
    var onRemove: () -> Void

    var body: some View {
        AxCard(radius: 18, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    IconTile(systemName: ExerciseIcons.symbol(for: draft.name, group: draft.muscleGroup),
                             color: draft.muscleGroup.color, size: 38, radius: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(draft.name).font(.axDisplay(15, .bold)).foregroundStyle(.axPrimary)
                        Text(draft.muscleGroup.rawValue.uppercased())
                            .font(.axMono(9, .semibold)).tracking(0.5)
                            .foregroundStyle(draft.muscleGroup.color)
                    }
                    Spacer()
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.axTertiary)
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 8) {
                    ForEach($draft.sets) { $set in
                        setRow($set)
                    }
                }

                Button {
                    var next = SetDraft()
                    next.weightText = draft.sets.last?.weightText ?? ""   // repeat last weight
                    draft.sets.append(next)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Add set")
                    }
                    .font(.axMono(11, .semibold))
                    .foregroundStyle(.axSecondary)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func setRow(_ set: Binding<SetDraft>) -> some View {
        let number = (draft.sets.firstIndex { $0.id == set.wrappedValue.id } ?? 0) + 1
        return HStack(spacing: 10) {
            Text("SET \(number)")
                .font(.axMono(10, .semibold)).tracking(0.5)
                .foregroundStyle(.axTertiary)
                .frame(width: 44, alignment: .leading)

            numberField("kg", text: set.weightText, decimal: true)
            Text("×").font(.axMono(12)).foregroundStyle(.axTertiary)
            numberField(draft.repsHint, text: set.repsText, decimal: false)

            Spacer()
            Image(systemName: set.wrappedValue.repsValue != nil ? "checkmark.circle.fill" : "circle.dotted")
                .font(.system(size: 16))
                .foregroundStyle(set.wrappedValue.repsValue != nil ? Color.axGreen : Color.axTertiary)

            if draft.sets.count > 1 {
                Button {
                    draft.sets.removeAll { $0.id == set.wrappedValue.id }
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(.axTertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func numberField(_ placeholder: String, text: Binding<String>, decimal: Bool) -> some View {
        TextField(placeholder, text: text)
            .font(.axMono(13, .semibold))
            .foregroundStyle(.axPrimary)
            .multilineTextAlignment(.center)
#if os(iOS)
            .keyboardType(decimal ? .decimalPad : .numberPad)
#endif
            .frame(width: 64)
            .padding(.vertical, 8)
            .background(Color.axInset)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Exercise picker (the client-side movement catalog, by muscle group)

private struct ExercisePickerView: View {
    var onPick: (String, MuscleGroup) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(MuscleGroup.allCases) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(group.rawValue.uppercased())
                            VStack(spacing: 8) {
                                ForEach(StrengthEngine.movements(for: group), id: \.self) { name in
                                    Button {
                                        onPick(name, group)
                                        dismiss()
                                    } label: {
                                        HStack(spacing: 12) {
                                            IconTile(systemName: ExerciseIcons.symbol(for: name, group: group),
                                                     color: group.color, size: 34, radius: 8)
                                            Text(name).font(.axDisplay(14, .semibold)).foregroundStyle(.axPrimary)
                                            Spacer()
                                            Image(systemName: "plus.circle")
                                                .font(.system(size: 16))
                                                .foregroundStyle(.axAccent)
                                        }
                                        .padding(12)
                                        .background(Color.axInset)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.axBackground)
            .navigationTitle("Add exercise")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
