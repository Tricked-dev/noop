import XCTest
@testable import StrandAnalytics

final class ActivityGuidanceTests: XCTestCase {
    private let anchor = "2026-09-22"
    private func points(_ count: Int = 14, value: Double = 6000, channel: String = "phone") -> [ActivityGuidance.Point] {
        (1...count).map { .init(day: MetricContext.shift(anchor, by: -$0), value: value, channel: channel) }
    }
    func testGuidelineEquivalentMinutesAcrossRequestedAdultAges() {
        // WHO 2020: 75 vigorous = 150 moderate; 60 moderate + 45 vigorous = 150.
        for age in 20...40 {
            XCTAssertEqual(ActivityGuidance.equivalentMinutes(moderate: 0, vigorous: 75, confirmedAge: age), 150)
            XCTAssertEqual(ActivityGuidance.equivalentMinutes(moderate: 60, vigorous: 45, confirmedAge: age), 150)
            XCTAssertEqual(ActivityGuidance.equivalentMinutes(moderate: 300, vigorous: 0, confirmedAge: age), 300)
        }
    }
    func testUnknownInvalidAndChildInputsDoNotBecomeZeroOrAdultAdvice() {
        for age in [nil, 17, 121] as [Int?] {
            XCTAssertNil(ActivityGuidance.equivalentMinutes(moderate: 150, vigorous: 0, confirmedAge: age))
        }
        for minutes in [nil, -.infinity, .infinity, .nan, -1, 10081] as [Double?] {
            XCTAssertNil(ActivityGuidance.equivalentMinutes(moderate: minutes, vigorous: 0, confirmedAge: 30))
        }
        XCTAssertNil(ActivityGuidance.equivalentMinutes(moderate: 6000, vigorous: 6000, confirmedAge: 30))
        XCTAssertEqual(ActivityGuidance.equivalentMinutes(moderate: 0, vigorous: 0, confirmedAge: 30), 0)
    }
    func testCompletedWeeksExcludeTodayAndFutureWithNoMissingDayZeros() {
        var rows = points()
        rows += [.init(day: anchor, value: 99999, channel: "phone"), .init(day: "2026-09-23", value: 99999, channel: "phone")]
        let result = ActivityGuidance.compare(rows, anchorDay: anchor)
        XCTAssertEqual(result.previous ?? -1, 6000, accuracy: 0.000001)
        XCTAssertEqual(result.recent ?? -1, 6000, accuracy: 0.000001)
        XCTAssertEqual(result.recentCount, 7)
        XCTAssertEqual(ActivityGuidance.walking(result), .maintained)
        rows.removeAll { ["2026-09-21", "2026-09-20", "2026-09-19"].contains($0.day) }
        let sparse = ActivityGuidance.compare(rows, anchorDay: anchor)
        XCTAssertNil(sparse.recent); XCTAssertNil(sparse.delta)
        XCTAssertEqual(ActivityGuidance.walking(sparse), .insufficient)
    }
    func testSourceChangesAndConflictingDuplicatesWithholdComparison() {
        var rows = points()
        rows[0] = .init(day: rows[0].day, value: 9000, channel: "other-device")
        XCTAssertNil(ActivityGuidance.compare(rows, anchorDay: anchor).delta)
        let conflicts = points() + points(3, value: 7000)
        XCTAssertEqual(ActivityGuidance.compare(conflicts, anchorDay: anchor).recentCount, 4)
        XCTAssertNil(ActivityGuidance.compare(conflicts, anchorDay: anchor).recent)
        XCTAssertEqual(ActivityGuidance.compare(points() + points(), anchorDay: anchor).recentCount, 7)
    }
    func testWalkingThresholdIsDescriptiveAndRequiresPositiveBaseline() {
        let rows = (1...14).map { ActivityGuidance.Point(day: MetricContext.shift(anchor, by: -$0), value: $0 <= 7 ? 4000 : 6000, channel: "phone") }
        XCTAssertEqual(ActivityGuidance.walking(ActivityGuidance.compare(rows, anchorDay: anchor)), .lower)
        XCTAssertEqual(ActivityGuidance.walking(ActivityGuidance.compare(points(value: 0), anchorDay: anchor)), .insufficient)
        XCTAssertNil(ActivityGuidance.compare(points(value: .nan), anchorDay: anchor).delta)
        XCTAssertNil(ActivityGuidance.compare(points(value: .greatestFiniteMagnitude), anchorDay: anchor).delta)
    }
    func testStrengthIsDistinctCompletedDaysNotSessionCount() {
        XCTAssertEqual(ActivityGuidance.strengthDays(["2026-09-21", "2026-09-21", "2026-09-15", "2026-09-14", anchor, "invalid"], anchorDay: anchor), 2)
        XCTAssertTrue(ActivityGuidance.isStrengthSport("traditionalstrengthtraining"))
        XCTAssertFalse(ActivityGuidance.isStrengthSport("yoga"))
        XCTAssertFalse(ActivityGuidance.isStrengthSport("hiit"))
    }
    func testUncalibratedAndMethodSensitiveMetricsCannotBypassQualityGates() {
        for key in ["spo2", "resp_rate", "hrv", "skin_temp", "rhr", "sleep_total_min", "vo2max_est", "fitness_age", "body_age", "unknown"] {
            XCTAssertFalse(MetricEvidence.allowsGenericComparison(key), key)
        }
        XCTAssertEqual(MetricEvidence.group(for: "steps_est"), .motionSteps)
        XCTAssertEqual(MetricEvidence.group(for: "sleep_rem_min"), .stages)
    }
}
