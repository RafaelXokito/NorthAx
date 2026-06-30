import Foundation

struct CoachMessage: Identifiable {
    var id = UUID()
    var content: String
    var isCoach: Bool
    var timestamp: Date

    static var opening: CoachMessage {
        CoachMessage(
            content: "Good morning. Based on your data today, your readiness is looking strong — your HRV has returned above baseline and sleep quality was excellent.\n\nWhat would you like to know?",
            isCoach: true,
            timestamp: Date()
        )
    }

    static let quickQuestions: [String] = [
        "Should I train today?",
        "Why is my recovery low?",
        "Am I overtraining?",
        "What should I focus on?",
        "Explain my training load"
    ]
}
