import SwiftUI

/// Sheet listing sports not yet enrolled (Plan §5b). Selecting one enrolls it
/// (adds to `enabledDomains`) and reports the choice back so the caller can show
/// the "include [Sport]? Regenerate now?" prompt.
struct EnrollSportSheet: View {
    @Environment(AthleteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Called with the newly enrolled sport so the caller can offer regeneration.
    let onEnroll: (TrainingDomain) -> Void

    private var available: [TrainingDomain] {
        TrainingDomain.allCases.filter { !store.enabledDomains.contains($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    if available.isEmpty {
                        Text("All sports are already enrolled.")
                            .font(.subheadline)
                            .foregroundStyle(.axSecondary)
                            .padding(.top, 40)
                    } else {
                        ForEach(available) { sportRow($0) }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .background(Color.axBackground)
            .navigationTitle("Add a Sport")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .scrollIndicators(.hidden)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func sportRow(_ domain: TrainingDomain) -> some View {
        Button {
            store.enabledDomains.append(domain)
            onEnroll(domain)
            dismiss()
        } label: {
            AxCard(radius: 16, padding: 16) {
                HStack(spacing: 14) {
                    IconTile(systemName: domain.icon, color: domain.color, size: 38)

                    Text(domain.rawValue)
                        .font(.axDisplay(15, .semibold))
                        .foregroundStyle(.axPrimary)

                    Spacer()

                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(domain.color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

#Preview {
    EnrollSportSheet { _ in }
        .environment(AthleteStore())
}
