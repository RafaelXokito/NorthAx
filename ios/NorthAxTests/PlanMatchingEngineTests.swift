import XCTest
@testable import NorthAx

final class PlanMatchingEngineTests: XCTestCase {
    private let cal = Calendar.current

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 8) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    func testPlannedMatchIsDoneAndOffPlanWorkoutIsExtra() {
        let monday = date(2026, 6, 1)
        let tuesday = date(2026, 6, 2)
        let week = WeeklyPlan(weekStart: monday, days: [
            PlannedDay(date: monday,
                       sessions: [PlannedSession(domain: .cycling, title: "Endurance ride",
                                                 subtitle: "", duration: 60, intensityLabel: "Easy")],
                       isRest: false),
            PlannedDay(date: tuesday, sessions: [], isRest: true),
        ])
        let ride = GarminActivity(id: "ride", name: "Morning Ride", type: .cycling,
                                  startTime: monday, duration: 3600)
        let run = GarminActivity(id: "run", name: "Surprise Run", type: .running,
                                 startTime: tuesday, duration: 1800)

        let matches = PlanMatchingEngine.matches(week: week, activities: [ride, run],
                                                 today: date(2026, 6, 3))

        let rideMatch = matches.first { $0.activity?.id == "ride" }
        XCTAssertEqual(rideMatch?.completion, .done)

        let runMatch = matches.first { $0.activity?.id == "run" }
        XCTAssertEqual(runMatch?.completion, .extra)
        XCTAssertEqual(runMatch?.session.domain, .running)

        XCTAssertTrue(SessionCompletion.extra.isCompleted)
        XCTAssertFalse(SessionCompletion.missed.isCompleted)

        // Day rollups: the planned day is done; the rest day with an off-plan
        // workout still rolls up as done for the week strip.
        XCTAssertEqual(PlanMatchingEngine.dayState(day: week.days[0], matches: matches), .done)
        XCTAssertEqual(PlanMatchingEngine.dayState(day: week.days[1], matches: matches), .done)
    }

    func testTodayMatchesShowExtrasEvenWithoutACoveringPlanWeek() {
        let today = date(2026, 6, 10)
        let run = GarminActivity(id: "run", name: "Lunch Run", type: .running,
                                 startTime: today, duration: 1800)

        // No plan at all — the workout still surfaces as an extra.
        let noPlan = PlanMatchingEngine.todayMatches(week: nil, activities: [run], today: today)
        XCTAssertEqual(noPlan.count, 1)
        XCTAssertEqual(noPlan.first?.completion, .extra)
        XCTAssertEqual(noPlan.first?.activity?.id, "run")

        // A lapsed plan week that doesn't contain today — same outcome.
        let staleMonday = date(2026, 6, 1)
        let staleWeek = WeeklyPlan(weekStart: staleMonday, days: [
            PlannedDay(date: staleMonday, sessions: [], isRest: true),
        ])
        let stale = PlanMatchingEngine.todayMatches(week: staleWeek, activities: [run], today: today)
        XCTAssertEqual(stale.count, 1)
        XCTAssertEqual(stale.first?.completion, .extra)

        // A week that covers today must not duplicate the extra.
        let monday = date(2026, 6, 8)
        let week = WeeklyPlan(weekStart: monday, days: [
            PlannedDay(date: monday, sessions: [], isRest: true),
            PlannedDay(date: date(2026, 6, 9), sessions: [], isRest: true),
            PlannedDay(date: today,
                       sessions: [PlannedSession(domain: .cycling, title: "Endurance ride",
                                                 subtitle: "", duration: 60, intensityLabel: "Easy")],
                       isRest: false),
        ])
        let covered = PlanMatchingEngine.todayMatches(week: week, activities: [run], today: today)
        XCTAssertEqual(covered.count, 2)
        XCTAssertEqual(covered.filter { $0.completion == .extra }.count, 1)
        XCTAssertEqual(covered.filter { $0.completion == .planned }.count, 1)
    }
}
