import SwiftUI

/// Sheet for logging today's wellness readings by hand. Values are sent as a
/// `manual` source and resolved against the user's other integrations by the
/// per-metric priority (see docs/multi-source-metrics.md). Blank fields are left
/// to whichever source normally provides them.
struct ManualEntryView: View {
    @Environment(AthleteStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var hrv = ""
    @State private var restingHR = ""
    @State private var sleep = ""
    @State private var weight = ""
    @State private var saving = false

    private var isEmpty: Bool {
        hrv.isEmpty && restingHR.isEmpty && sleep.isEmpty && weight.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Enter today's readings by hand. Blank fields are left to your other sources, following your Data Priority settings.")
                        .font(.subheadline)
                        .foregroundStyle(.axSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 10) {
                        field("Heart Rate Variability", unit: "ms", text: $hrv)
                        field("Resting Heart Rate", unit: "bpm", text: $restingHR)
                        field("Sleep", unit: "hrs", text: $sleep)
                        field("Body Weight", unit: "kg", text: $weight)
                    }
                }
                .padding(20)
            }
            .background(Color.axBackground)
            .navigationTitle("Log Metrics")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(saving || isEmpty)
                }
            }
        }
    }

    private func field(_ label: String, unit: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
            TextField("—", text: text)
#if os(iOS)
                .keyboardType(.decimalPad)
#endif
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.white)
                .frame(width: 70)
            Text(unit)
                .font(.caption)
                .foregroundStyle(.axSecondary)
                .frame(width: 34, alignment: .leading)
        }
        .padding(16)
        .background(Color.axSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.axBorder, lineWidth: 1))
    }

    private func save() {
        saving = true
        func num(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }
        Task {
            await store.submitManualMetrics(
                hrv: num(hrv),
                restingHR: num(restingHR).map { Int($0.rounded()) },
                sleepHours: num(sleep),
                weight: num(weight)
            )
            dismiss()
        }
    }
}
