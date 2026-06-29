import SwiftUI

enum TrainingDomain: String, Codable, CaseIterable, Identifiable {
    case cycling   = "Cycling"
    case running   = "Running"
    case strength  = "Strength"
    case swimming  = "Swimming"
    case triathlon = "Triathlon"
    case mobility  = "Mobility"
    case recovery  = "Recovery"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .cycling:   return "bicycle"
        case .running:   return "figure.run"
        case .strength:  return "dumbbell"
        case .swimming:  return "figure.pool.swim"
        case .triathlon: return "trophy"
        case .mobility:  return "figure.flexibility"
        case .recovery:  return "heart.circle"
        }
    }

    var color: Color {
        switch self {
        case .cycling:   return .axAccent
        case .running:   return .axGreen
        case .strength:  return .axRed
        case .swimming:  return .axBlue
        case .triathlon: return .axPurple
        case .mobility:  return Color(red: 0.9, green: 0.7, blue: 0.2)
        case .recovery:  return Color(red: 0.3, green: 0.8, blue: 0.7)
        }
    }
}
