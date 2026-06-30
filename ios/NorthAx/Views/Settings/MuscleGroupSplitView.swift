import SwiftUI

struct MuscleGroupSplitView: View {
    @Environment(AthleteStore.self) private var store
    @State private var editingDayIndex: Int? = nil

    private let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                presetPicker
                weekGrid
                if let idx = editingDayIndex {
                    dayEditor(for: idx)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color.axBackground)
        .navigationTitle("Muscle Group Split")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .scrollIndicators(.hidden)
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.axPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(Color.axSurface)
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
        @Bindable var bindable = store
        let split = store.muscleGroupSplit.days[idx]
        let isEditing = editingDayIndex == idx

        return Button {
            editingDayIndex = isEditing ? nil : idx
        } label: {
            HStack(spacing: 12) {
                Text(dayNames[idx])
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.axSecondary)
                    .frame(width: 34, alignment: .leading)

                if split.isRestDay || split.muscleGroups.isEmpty {
                    Text("Rest")
                        .font(.subheadline)
                        .foregroundStyle(.axTertiary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(split.muscleGroups) { group in
                                Text(group.rawValue)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(group.color)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(group.color.opacity(0.10))
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
            .background(isEditing ? Color.axSurface.opacity(1.5) : Color.axSurface)
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
            .font(.subheadline)
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
                    .font(.subheadline)
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
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.axTertiary)
            .tracking(2)
    }
}

#Preview {
    NavigationStack {
        MuscleGroupSplitView()
            .environment(AthleteStore())
    }
}
