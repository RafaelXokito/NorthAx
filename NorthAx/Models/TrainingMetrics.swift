import Foundation

struct TrainingMetrics {
    // HRV
    var hrv: Double           // ms, today's morning reading
    var hrvBaseline: Double   // 7-day rolling average
    var hrvTrend: [Double]    // last 7 days (oldest → newest)

    // Heart Rate
    var restingHR: Int
    var restingHRBaseline: Int

    // Sleep
    var sleepDuration: Double  // hours
    var sleepScore: Int        // 0–100
    var remSleep: Double       // hours
    var deepSleep: Double      // hours
    var sleepDebt: Double      // cumulative hours shortfall

    // Training Load (Banister impulse–response model)
    var acuteLoad: Double      // 7-day ATL (Acute Training Load)
    var chronicLoad: Double    // 42-day CTL (Chronic Training Load)
    var todayLoad: Double      // today's planned training stress
    var weeklyLoadChange: Double  // fraction vs previous week

    // Optional
    var bodyWeight: Double?    // kg

    // Derived
    var trainingBalance: Double { chronicLoad - acuteLoad }  // positive = fresh
    var trainingRatio: Double   { acuteLoad / max(1, chronicLoad) }
    var hrvChange: Double       { (hrv - hrvBaseline) / max(1, hrvBaseline) }
    var restingHRChange: Int    { restingHR - restingHRBaseline }

    // MARK: - Mock data

    static var mockFresh: TrainingMetrics {
        TrainingMetrics(
            hrv: 58, hrvBaseline: 54,
            hrvTrend: [51, 49, 52, 54, 53, 56, 58],
            restingHR: 46, restingHRBaseline: 47,
            sleepDuration: 7.5, sleepScore: 84,
            remSleep: 1.8, deepSleep: 1.4, sleepDebt: 0.3,
            acuteLoad: 68, chronicLoad: 72,
            todayLoad: 0, weeklyLoadChange: 0.08,
            bodyWeight: 78.2
        )
    }

    static var mockFatigued: TrainingMetrics {
        TrainingMetrics(
            hrv: 42, hrvBaseline: 54,
            hrvTrend: [54, 53, 51, 48, 45, 43, 42],
            restingHR: 54, restingHRBaseline: 47,
            sleepDuration: 5.8, sleepScore: 58,
            remSleep: 1.0, deepSleep: 0.8, sleepDebt: 3.2,
            acuteLoad: 98, chronicLoad: 72,
            todayLoad: 0, weeklyLoadChange: 0.28,
            bodyWeight: 78.8
        )
    }
}
