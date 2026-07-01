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

    // Daily history for the detail graphs (oldest→newest, aligned with `trendDates`).
    // Empty when no backend history is available (e.g. HealthKit-only sessions).
    var trendDates: [Date] = []
    var hrvSeries: [Double] = []
    var restingHRSeries: [Double] = []
    var sleepSeries: [Double] = []
    var tsbSeries: [Double] = []   // Fitness − Fatigue (chronicLoad − acuteLoad)

    /// Which source won each mergeable metric (keyed by `MergeableMetric.rawValue`),
    /// filled in by `MetricResolver`. Empty when there's only one source.
    var provenance: [String: MetricSource] = [:]

    func source(for metric: MergeableMetric) -> MetricSource? { provenance[metric.rawValue] }

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
            bodyWeight: 78.2,
            trendDates: mockDates(),
            hrvSeries: ramp(from: 49, to: 58, wiggle: 2.5),
            restingHRSeries: ramp(from: 49, to: 46, wiggle: 1),
            sleepSeries: ramp(from: 6.6, to: 7.5, wiggle: 0.45),
            tsbSeries: ramp(from: -3, to: 4, wiggle: 3),
            provenance: [
                MergeableMetric.hrv.rawValue: .healthkit,
                MergeableMetric.restingHR.rawValue: .intervals,
                MergeableMetric.sleep.rawValue: .intervals
            ]
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
            bodyWeight: 78.8,
            trendDates: mockDates(),
            hrvSeries: ramp(from: 55, to: 42, wiggle: 2.5),
            restingHRSeries: ramp(from: 47, to: 54, wiggle: 1),
            sleepSeries: ramp(from: 7.2, to: 5.8, wiggle: 0.5),
            tsbSeries: ramp(from: 3, to: -26, wiggle: 3.5),
            provenance: [
                MergeableMetric.hrv.rawValue: .healthkit,
                MergeableMetric.restingHR.rawValue: .intervals,
                MergeableMetric.sleep.rawValue: .intervals
            ]
        )
    }

    /// Last `count` calendar days, oldest→newest, for mock graph series.
    static func mockDates(_ count: Int = 30) -> [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<count).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
    }

    /// Believable synthetic series: a linear drift from `from`→`to` with a gentle
    /// sinusoidal wiggle so the mock graphs don't look like straight lines.
    private static func ramp(from a: Double, to b: Double, count: Int = 30, wiggle: Double) -> [Double] {
        (0..<count).map { i in
            let t = Double(i) / Double(count - 1)
            return a + (b - a) * t + sin(Double(i) * 1.3) * wiggle
        }
    }
}
