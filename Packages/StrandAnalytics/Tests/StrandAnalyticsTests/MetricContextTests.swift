import XCTest
@testable import StrandAnalytics

final class MetricContextTests: XCTestCase {
    private let anchor = "2026-09-22"
    private let adult = MetricContext.Profile(confirmedAge: 30, sex: "male", heightCM: 180)

    private func row(_ metric: MetricContext.Metric = .restingHR, offset: Int, value: Double,
                     channel: String = "whoop4:no-op", verified: Bool = true,
                     use: MetricContext.MeasurementUse = .estimate) -> MetricContext.Observation {
        .init(metric, day: MetricContext.shift(anchor, by: offset), value: value,
              channel: channel, verified: verified, use: use)
    }
    private func history(_ metric: MetricContext.Metric = .restingHR, value: Double = 60) -> [MetricContext.Observation] {
        (-30 ... -1).map { row(metric, offset: $0, value: value) }
    }
    private func reading(_ rows: [MetricContext.Observation], metric: MetricContext.Metric = .restingHR) -> MetricContext.Reading {
        MetricContext.reading(metric: metric, observations: rows, anchorDay: anchor, profile: adult)
    }

    func testAdultSleepMinimumMatchesAASMForEntireRequestedAgeHeightGrid() {
        // AASM/SRS 2015, doi:10.5664/jcsm.4758: ages 18–60, >=7h; no upper limit.
        // Height and sex are not coefficients in that recommendation. Test every requested cm/year.
        for age in 20...40 {
            for height in 160...200 {
                let target = MetricContext.sleepTarget(profile: .init(confirmedAge: age, sex: "male", heightCM: Double(height)))
                XCTAssertEqual(target?.lower, 420)
                XCTAssertNil(target?.upper)
            }
        }
    }

    func testSleepAgeBoundariesMatchCDCTableAndUnknownAgeDoesNotDefaultToThirty() {
        for (age, lower, upper) in [(13,480,600), (17,480,600), (18,420,-1), (60,420,-1), (61,420,540), (64,420,540), (65,420,480), (100,420,480)] {
            let target = MetricContext.sleepTarget(profile: .init(confirmedAge: age))
            XCTAssertEqual(target?.lower, Double(lower))
            XCTAssertEqual(target?.upper, upper == -1 ? nil : Double(upper))
        }
        XCTAssertNil(MetricContext.sleepTarget(profile: .init(confirmedAge: nil)))
        XCTAssertNil(MetricContext.sleepTarget(profile: .init(confirmedAge: 12)))
        XCTAssertNil(MetricContext.sleepTarget(profile: .init(confirmedAge: 121)))
        let longNight = reading([row(.sleep, offset: 0, value: 620)], metric: .sleep)
        XCTAssertEqual(longNight.state, .within, "No invented upper limit for adults 18–60")
    }

    func testPersonalBoundsAgreeWithExistingVitalBandsAtBoundaries() {
        let prior = history()
        let reference = reading(prior + [row(offset: 0, value: 60)])
        XCTAssertEqual(reference.basis, .personal)
        for value in [reference.lower! - 0.01, reference.lower!, 60, reference.upper!, reference.upper! + 0.01] {
            let context = reading(prior + [row(offset: 0, value: value)])
            let legacy = VitalBands.band(value: value, history: prior.map { Optional($0.value) },
                                         populationRange: 50...90, cfg: Baselines.restingHRCfg)
            XCTAssertEqual(context.state == .within, legacy.band == .inRange)
        }
    }

    func testNoPopulationHRVJudgmentForYoungTallOrShortMen() {
        for age in [20, 25, 30, 35, 40] {
            for height in [160.0, 180, 200] {
                let result = MetricContext.reading(metric: .hrv, observations: [row(.hrv, offset: 0, value: 35)],
                    anchorDay: anchor, profile: .init(confirmedAge: age, sex: "male", heightCM: height))
                XCTAssertEqual(result.state, .learning)
                XCTAssertNil(result.lower)
                XCTAssertEqual(result.basis, .none)
            }
        }
    }

    func testResetPreventsWeeklyComparisonAcrossMeasurementSettings() {
        let rows = (-14 ... -1).map { row(.hrv, offset: $0, value: $0 < -7 ? 45 : 60) }
        let snapshot = MetricContext.evaluate(observations: rows, anchorDay: anchor, profile: adult,
            hrvResetDay: MetricContext.shift(anchor, by: -7))
        XCTAssertNil(snapshot.comparisons.first { $0.metric == .hrv }?.delta)
        XCTAssertFalse(snapshot.insights.contains { $0.metric == .hrv })
    }

    func testTodayAndFutureCannotMovePersonalReference() {
        let normal = reading(history() + [row(offset: 0, value: 60)])
        let high = reading(history() + [row(offset: 0, value: 90), row(offset: 1, value: 180)])
        XCTAssertEqual(high.lower, normal.lower)
        XCTAssertEqual(high.upper, normal.upper)
        XCTAssertEqual(high.state, .above)
    }

    func testCalendarGapMakesBaselineStaleAndOldReadingsCannotBeCurrent() {
        let old = (-50 ... -20).map { row(offset: $0, value: 60) }
        XCTAssertEqual(reading(old + [row(offset: 0, value: 60)]).state, .stale)
        XCTAssertEqual(reading(old).state, .stale)
        XCTAssertNil(reading(old).lower)
    }

    func testSourceSwitchAndResetRequireNewReference() {
        let switched = reading(history() + [row(offset: 0, value: 60, channel: "new-device")])
        XCTAssertEqual(switched.state, .learning)
        XCTAssertEqual(switched.nights, 0)
        let reset = MetricContext.reading(metric: .restingHR, observations: history() + [row(offset: 0, value: 60)],
                                         anchorDay: anchor, profile: adult, resetDay: MetricContext.shift(anchor, by: -3))
        XCTAssertEqual(reset.nights, 3)
        XCTAssertEqual(reset.state, .learning)
    }

    func testInvalidAndUnverifiedReadingsDoNotProduceRanges() {
        for value in [Double.nan, .infinity, -1, 900] {
            XCTAssertEqual(reading(history() + [row(offset: 0, value: value)]).state, .unverified)
        }
        XCTAssertEqual(reading(history() + [row(offset: 0, value: 60, verified: false)]).state, .unverified)
        let unknown = reading([row(.hrv, offset: 0, value: 45, channel: "")], metric: .hrv)
        XCTAssertEqual(unknown.state, .unverified)
    }

    func testWeeklyMeansUseCompletedCalendarWindowsAndIgnoreToday() {
        let rows = (-14 ... -8).map { row(offset: $0, value: 60) }
            + (-7 ... -1).map { row(offset: $0, value: 64) } + [row(offset: 0, value: 100)]
        let result = MetricContext.compare(metric: .restingHR, observations: rows, anchorDay: anchor)
        XCTAssertEqual(result.previous.start, "2026-09-08")
        XCTAssertEqual(result.recent.end, "2026-09-21")
        XCTAssertEqual(result.previous.count, 7)
        XCTAssertEqual(result.delta, 4)
    }

    func testMissingDaysAreNotZerosAndEffortRequiresCompleteWeeks() {
        let rows = (-14 ... -1).filter { $0 != -3 }.map { row(.effort, offset: $0, value: 20) }
        let result = MetricContext.compare(metric: .effort, observations: rows, anchorDay: anchor)
        XCTAssertEqual(result.previous.value, 140)
        XCTAssertNil(result.recent.value)
        XCTAssertNil(result.delta)
        let tooFew = (-4 ... -1).map { row(offset: $0, value: 60) }
        XCTAssertNil(MetricContext.compare(metric: .restingHR, observations: tooFew, anchorDay: anchor).recent.value)
    }

    func testMixedSourcesNeverProduceWeeklyComparison() {
        let rows = (-14 ... -8).map { row(.hrv, offset: $0, value: 40, channel: "rmssd") }
            + (-7 ... -1).map { row(.hrv, offset: $0, value: 80, channel: "sdnn") }
        let result = MetricContext.compare(metric: .hrv, observations: rows, anchorDay: anchor)
        XCTAssertFalse(result.compatible)
        XCTAssertNil(result.delta)
    }

    func testMidnightBedtimeConsistencyAndCalendarDSTBoundaries() {
        let rows = (-14 ... -1).map { row(.bedtime, offset: $0, value: $0.isMultiple(of: 2) ? 1435 : 5) }
        let result = MetricContext.compare(metric: .bedtime, observations: rows, anchorDay: anchor)
        XCTAssertLessThan(result.recent.value!, 6)
        XCTAssertEqual(MetricContext.shift("2026-03-29", by: 1), "2026-03-30")
        XCTAssertEqual(MetricContext.shift("2026-10-25", by: -1), "2026-10-24")
        XCTAssertEqual(MetricContext.shift("2026-02-30", by: 0), "")
    }

    func testWhoop4ReliabilityGatesAdviceAndRawRespiration() {
        XCTAssertEqual(MetricContext.whoop4Use(.restingHR), .estimate)
        XCTAssertEqual(MetricContext.whoop4Use(.skinTemperature), .trendOnly)
        XCTAssertEqual(MetricContext.whoop4Use(.hrv), .trendOnly)
        XCTAssertEqual(MetricContext.whoop4Use(.respiration), .unverified)
        let sleep = (-2...0).map { row(.sleep, offset: $0, value: 300, use: .trendOnly) }
        let result = MetricContext.evaluate(observations: sleep, anchorDay: anchor, profile: adult)
        XCTAssertFalse(result.insights.contains { $0.kind == .sleepOpportunity })
        XCTAssertEqual(result.readings.first { $0.metric == .sleep }?.state, .descriptive)
        XCTAssertEqual(reading([row(.respiration, offset: 0, value: 16, use: .unverified)], metric: .respiration).state, .unverified)
    }

    func testSleepAdviceRequiresThreeActualReliableNightsAndConfirmedAge() {
        let sleep = (-2...0).map { row(.sleep, offset: $0, value: 360) }
        XCTAssertTrue(MetricContext.evaluate(observations: sleep, anchorDay: anchor, profile: adult).insights.contains { $0.kind == .sleepOpportunity })
        XCTAssertFalse(MetricContext.evaluate(observations: Array(sleep.dropLast()), anchorDay: anchor, profile: adult).insights.contains { $0.kind == .sleepOpportunity })
        XCTAssertTrue(MetricContext.evaluate(observations: sleep, anchorDay: anchor, profile: .init(confirmedAge: nil)).insights.isEmpty)
    }

    func testSustainedChangesRequireActualConsecutiveDaysAndDoNotDuplicateVitals() {
        let rows = history() + history(.hrv, value: 50)
        let withoutRecent = rows.filter { $0.day < MetricContext.shift(anchor, by: -2) }
        let new = (-2...0).flatMap { [row(offset: $0, value: 80), row(.hrv, offset: $0, value: 20)] }
        let result = MetricContext.evaluate(observations: withoutRecent + new, anchorDay: anchor, profile: adult)
        XCTAssertEqual(result.insights.filter { $0.kind == .sustainedChange }.count, 1)
        XCTAssertLessThanOrEqual(result.insights.count, 3)
        let gap = new.filter { $0.day != MetricContext.shift(anchor, by: -1) }
        XCTAssertFalse(MetricContext.evaluate(observations: withoutRecent + gap, anchorDay: anchor, profile: adult).insights.contains { $0.kind == .sustainedChange })
    }
}
