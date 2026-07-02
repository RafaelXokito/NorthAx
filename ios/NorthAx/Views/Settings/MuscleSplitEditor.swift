import SwiftUI

/// Reusable inline editor for the weekly muscle-group split (preset picker +
/// tap-to-edit day grid + per-day muscle toggles). Embedded in the Gym config
/// block of TrainingPlanView. (The former standalone MuscleGroupSplitView screen
/// has been removed; this is now an inline component.)
struct MuscleSplitEditor: View {
    @Environment(AthleteStore.self) private var store
    @State private var editingDayIndex: Int? = nil

    private let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        VStack(spacing: 16) {
            presetPicker
            weekGrid
            if let idx = editingDayIndex {
                dayEditor(for: idx)
            }
        }
        .animation(.spring(duration: 0.3), value: editingDayIndex)
    }

    // MARK: - Preset picker

    private var presetPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("PRESET SPLITS")

            HStack(spacing: 10) {
                presetButton("Push / Pull / Legs", split: .pushPullLegs)
                presetButton("Upper / Lower",       split: .upperLower)
                presetButton("Full Body",            split: .fullBody)
            }
        }
    }

    private func presetButton(_ title: String, split: WeeklyMuscleGroupSplit) -> some View {
        Button {
            store.muscleGroupSplit = split
            editingDayIndex = nil
        } label: {
            Text(title)
                .font(.axDisplay(12, .semibold))
                .foregroundStyle(.axPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(Color.axInset)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.axBorder, lineWidth: 1))
        }
    }

    // MARK: - Week grid

    private var weekGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("WEEKLY PLAN  ·  TAP TO EDIT")

            VStack(spacing: 8) {
                ForEach(0..<7) { idx in
                    weekRow(for: idx)
                }
            }
        }
    }

    private func weekRow(for idx: Int) -> some View {
        let split = store.muscleGroupSplit.days[idx]
        let isEditing = editingDayIndex == idx

        return Button {
            editingDayIndex = isEditing ? nil : idx
        } label: {
            HStack(spacing: 12) {
                Text(dayNames[idx].uppercased())
                    .font(.axMono(10, .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.axSecondary)
                    .frame(width: 38, alignment: .leading)

                if split.isRestDay || split.muscleGroups.isEmpty {
                    Text("Rest")
                        .font(.axDisplay(13))
                        .foregroundStyle(.axTertiary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(split.muscleGroups) { group in
                                Text(group.rawValue.uppercased())
                                    .font(.axMono(10, .semibold))
                                    .tracking(0.6)
                                    .foregroundStyle(group.color)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(group.color.opacity(0.14))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                Spacer()

                Image(systemName: isEditing ? "chevron.up" : "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.axTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.axSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isEditing ? Color.axAccent.opacity(0.4) : Color.axBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Day editor

    private func dayEditor(for idx: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("EDIT \(dayNames[idx].uppercased())")

            // Rest toggle
            Toggle("Rest Day", isOn: Binding(
                get: { store.muscleGroupSplit.days[idx].isRestDay },
                set: {
                    store.muscleGroupSplit.days[idx].isRestDay = $0
                    if $0 { store.muscleGroupSplit.days[idx].muscleGroups = [] }
                }
            ))
            .font(.axDisplay(13.5, .medium))
            .foregroundStyle(.axPrimary)
            .tint(.axAccent)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.axSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.axBorder, lineWidth: 1))

            if !store.muscleGroupSplit.days[idx].isRestDay {
                VStack(spacing: 8) {
                    ForEach(MuscleGroup.allCases) { group in
                        muscleGroupToggle(group, dayIndex: idx)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.axSurface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.axAccent.opacity(0.2), lineWidth: 1))
    }

    private func muscleGroupToggle(_ group: MuscleGroup, dayIndex: Int) -> some View {
        let isSelected = store.muscleGroupSplit.days[dayIndex].muscleGroups.contains(group)

        return Button {
            if isSelected {
                store.muscleGroupSplit.days[dayIndex].muscleGroups.removeAll { $0 == group }
            } else {
                store.muscleGroupSplit.days[dayIndex].muscleGroups.append(group)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: group.icon)
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? group.color : .axTertiary)
                    .frame(width: 32, height: 32)
                    .background((isSelected ? group.color : Color.white).opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(group.rawValue)
                    .font(.axDisplay(13.5, .medium))
                    .foregroundStyle(isSelected ? .axPrimary : .axSecondary)

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? group.color : .axTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? group.color.opacity(0.07) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text).axSectionLabel()
    }
}

#Preview {
    ScrollView {
        MuscleSplitEditor()
            .padding(20)
    }
    .background(Color.axBackground)
    .environment(AthleteStore())
}
