import SwiftUI

/// Reusable Mon–Sun pill selector for a single sport's training weekdays.
/// Reads/writes `store.trainingFrequency` (0=Mon … 6=Sun wire encoding); each
/// toggle mutates the store, which triggers local plan regen + server sync.
struct WeekdayGridView: View {
    @Environment(AthleteStore.self) private var store
    let domain: TrainingDomain

    // 0=Mon … 6=Sun (wire weekday encoding).
    private let labels = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        let days = store.trainingFrequency.weekdays(for: domain)
        return HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { wd in
                let on = days.contains(wd)
                Button {
                    store.trainingFrequency.toggle(wd, for: domain)
                } label: {
                    Text(labels[wd])
                        .font(.axMono(12, .semibold))
                        .foregroundStyle(on ? Color.axBackground : .axTertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(on ? domain.color : Color.axInset)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }
}

#Preview {
    WeekdayGridView(domain: .cycling)
        .environment(AthleteStore())
        .padding()
        .background(Color.axBackground)
}
