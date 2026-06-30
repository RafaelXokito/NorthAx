import Foundation

enum PaceUnit: String, Codable { case km, mile }
enum PoolUnit: String, Codable { case pool25m, pool50m, openWater }

/// Athlete physiological thresholds used at render time to compute training
/// zones (the GRAPH agent owns ZoneMath; this model just carries the data).
struct AthleteThresholds: Codable, Equatable {
    var ftpWatts: Int?
    var thresholdHr: Int?
    var maxHr: Int?
    var runThresholdPaceSecPerKm: Int?
    var paceUnit: PaceUnit
    var swimThresholdPaceSecPer100m: Int?
    var poolUnit: PoolUnit

    init(
        ftpWatts: Int? = nil,
        thresholdHr: Int? = nil,
        maxHr: Int? = nil,
        runThresholdPaceSecPerKm: Int? = nil,
        paceUnit: PaceUnit = .km,
        swimThresholdPaceSecPer100m: Int? = nil,
        poolUnit: PoolUnit = .pool25m
    ) {
        self.ftpWatts = ftpWatts
        self.thresholdHr = thresholdHr
        self.maxHr = maxHr
        self.runThresholdPaceSecPerKm = runThresholdPaceSecPerKm
        self.paceUnit = paceUnit
        self.swimThresholdPaceSecPer100m = swimThresholdPaceSecPer100m
        self.poolUnit = poolUnit
    }
}
