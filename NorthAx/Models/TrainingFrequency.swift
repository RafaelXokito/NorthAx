import Foundation

struct DomainFrequency: Codable, Identifiable, Equatable {
    var id: String { domain.id }
    var domain: TrainingDomain
    var daysPerWeek: Int  // 0–6
}

struct TrainingFrequency: Codable, Equatable {
    var domainFrequencies: [DomainFrequency]

    var totalTrainingDays: Int { domainFrequencies.reduce(0) { $0 + $1.daysPerWeek } }
    var restDaysPerWeek: Int   { max(0, 7 - totalTrainingDays) }
    var isOverloaded: Bool     { totalTrainingDays > 6 }

    func days(for domain: TrainingDomain) -> Int {
        domainFrequencies.first(where: { $0.domain == domain })?.daysPerWeek ?? 0
    }

    mutating func setDays(_ days: Int, for domain: TrainingDomain) {
        let clamped = max(0, min(days, 6))
        if let idx = domainFrequencies.firstIndex(where: { $0.domain == domain }) {
            if clamped == 0 {
                domainFrequencies.remove(at: idx)
            } else {
                domainFrequencies[idx].daysPerWeek = clamped
            }
        } else if clamped > 0 {
            domainFrequencies.append(DomainFrequency(domain: domain, daysPerWeek: clamped))
        }
    }

    // MARK: - Defaults

    static var defaultFrequency: TrainingFrequency {
        TrainingFrequency(domainFrequencies: [
            DomainFrequency(domain: .cycling,  daysPerWeek: 3),
            DomainFrequency(domain: .strength, daysPerWeek: 2)
        ])
    }

    static var empty: TrainingFrequency {
        TrainingFrequency(domainFrequencies: [])
    }
}
