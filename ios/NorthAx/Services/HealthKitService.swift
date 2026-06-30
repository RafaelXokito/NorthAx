import Foundation
import Observation
import HealthKit

/// Wraps `HKHealthStore` (Plan §4). Reads recovery metrics to supplement
/// readiness when Garmin/intervals.icu isn't connected, and writes completed
/// sessions back as `HKWorkout`s. Read and write are toggled independently and
/// persisted in UserDefaults. Mirrors `IntervalsService`'s shape: `@Observable`,
/// injected via the store, surfaced in Settings.
@MainActor
@Observable
class HealthKitService {

    /// Whether HealthKit exists on this device (false on iPad without pairing).
    let isAvailable = HKHealthStore.isHealthDataAvailable()

    /// User toggles, persisted. Reads/writes only run when the matching flag is on.
    var readEnabled: Bool = UserDefaults.standard.bool(forKey: Keys.read) {
        didSet { UserDefaults.standard.set(readEnabled, forKey: Keys.read) }
    }
    var writeEnabled: Bool = UserDefaults.standard.bool(forKey: Keys.write) {
        didSet { UserDefaults.standard.set(writeEnabled, forKey: Keys.write) }
    }

    private let store = HKHealthStore()

    private enum Keys {
        static let read  = "northax.healthkit.readEnabled"
        static let write = "northax.healthkit.writeEnabled"
    }

    // MARK: - Authorization types

    private var readTypes: Set<HKObjectType> {
        var set: Set<HKObjectType> = [HKObjectType.workoutType()]
        let quantities: [HKQuantityTypeIdentifier] = [
            .restingHeartRate, .heartRateVariabilitySDNN, .vo2Max,
            .activeEnergyBurned, .basalEnergyBurned, .stepCount,
            .distanceWalkingRunning, .bodyMass, .bodyFatPercentage
        ]
        quantities.forEach { if let t = HKQuantityType.quantityType(forIdentifier: $0) { set.insert(t) } }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) { set.insert(sleep) }
        return set
    }

    private var writeTypes: Set<HKSampleType> {
        var set: Set<HKSampleType> = [HKObjectType.workoutType()]
        [HKQuantityTypeIdentifier.activeEnergyBurned, .distanceWalkingRunning].forEach {
            if let t = HKQuantityType.quantityType(forIdentifier: $0) { set.insert(t) }
        }
        return set
    }

    /// Requests read + write authorization. The system only ever shows the
    /// prompt once per type; afterward this is a cheap no-op.
    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
    }

    // MARK: - Reads

    /// Latest resting heart rate (bpm).
    func latestRestingHR() async -> Int? {
        guard let v = await latestQuantity(.restingHeartRate, unit: .count().unitDivided(by: .minute())) else { return nil }
        return Int(v.rounded())
    }

    /// Latest HRV / SDNN (ms).
    func latestHRV() async -> Double? {
        await latestQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
    }

    /// Latest VO2 Max (mL/kg·min).
    func latestVO2Max() async -> Double? {
        let unit = HKUnit.literUnit(with: .milli)
            .unitDivided(by: .gramUnit(with: .kilo))
            .unitDivided(by: .minute())
        return await latestQuantity(.vo2Max, unit: unit)
    }

    /// Latest body weight (kg).
    func latestWeight() async -> Double? {
        await latestQuantity(.bodyMass, unit: .gramUnit(with: .kilo))
    }

    /// Latest body fat (fraction 0–1).
    func latestBodyFat() async -> Double? {
        await latestQuantity(.bodyFatPercentage, unit: .percent())
    }

    /// Today's active energy burned (kcal).
    func todayActiveEnergy() async -> Double? {
        await todaySum(.activeEnergyBurned, unit: .kilocalorie())
    }

    /// Today's step count.
    func todaySteps() async -> Double? {
        await todaySum(.stepCount, unit: .count())
    }

    /// Today's walking/running distance (metres).
    func todayDistance() async -> Double? {
        await todaySum(.distanceWalkingRunning, unit: .meter())
    }

    /// Last night's asleep duration (hours), summing all "asleep" category values.
    func lastNightSleepHours() async -> Double? {
        guard isAvailable, readEnabled,
              let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }

        // Window: yesterday 18:00 → now, so a normal night falls inside it.
        let end = Date()
        let start = Calendar.current.date(byAdding: .hour, value: -18, to: end) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
        ]

        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let total = (samples as? [HKCategorySample])?
                    .filter { asleepValues.contains($0.value) }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } ?? 0
                cont.resume(returning: total > 0 ? total / 3600.0 : nil)
            }
            store.execute(q)
        }
    }

    // MARK: - Read helpers

    /// Most recent sample value for a quantity type, in `unit`.
    private func latestQuantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard isAvailable, readEnabled,
              let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                cont.resume(returning: value)
            }
            store.execute(q)
        }
    }

    /// Sum of a cumulative quantity for today, in `unit`.
    private func todaySum(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard isAvailable, readEnabled,
              let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                      options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }
}

// MARK: - Writes

extension HealthKitService {

    /// Writes a completed planned session as an `HKWorkout` (Plan §4). No-op if
    /// HealthKit is unavailable or writing is disabled. `distance` is metres,
    /// `activeCalories` is kcal; both optional.
    func saveWorkout(
        domain: TrainingDomain,
        title: String,
        start: Date,
        end: Date,
        distance: Double? = nil,
        activeCalories: Double? = nil
    ) async {
        guard isAvailable, writeEnabled else { return }

        let config = HKWorkoutConfiguration()
        config.activityType = activityType(for: domain)

        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: start)

            var samples: [HKSample] = []
            if let kcal = activeCalories,
               let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
                let q = HKQuantity(unit: .kilocalorie(), doubleValue: kcal)
                samples.append(HKCumulativeQuantitySample(type: type, quantity: q, start: start, end: end))
            }
            if let metres = distance, metres > 0,
               let type = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
                let q = HKQuantity(unit: .meter(), doubleValue: metres)
                samples.append(HKCumulativeQuantitySample(type: type, quantity: q, start: start, end: end))
            }
            if !samples.isEmpty { try await builder.addSamples(samples) }

            try await builder.addMetadata([HKMetadataKeyWorkoutBrandName: "NorthAx — \(title)"])
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            // A failed write isn't fatal; the session is still marked done locally.
        }
    }

    /// Maps a NorthAx training domain to the closest HealthKit activity type.
    private func activityType(for domain: TrainingDomain) -> HKWorkoutActivityType {
        switch domain {
        case .cycling:   return .cycling
        case .running:   return .running
        case .swimming:  return .swimming
        case .strength:  return .traditionalStrengthTraining
        case .triathlon: return .crossTraining
        case .mobility:  return .flexibility
        case .recovery:  return .preparationAndRecovery
        }
    }
}
