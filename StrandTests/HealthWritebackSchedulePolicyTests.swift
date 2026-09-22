import XCTest
@testable import Strand

final class HealthWritebackSchedulePolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testSchedulesOnlyAfterAppleHealthAuthorization() {
        XCTAssertTrue(HealthWritebackSchedulePolicy.shouldSchedule(isAuthorized: true))
        XCTAssertFalse(HealthWritebackSchedulePolicy.shouldSchedule(isAuthorized: false))
    }

    func testIdleRepairIsDailyAndSuccessfulExportClearsHourlyRetry() {
        var state = HealthWritebackScheduleState(now: now)
        XCTAssertEqual(state.nextDate, now.addingTimeInterval(86_400))
        let token = state.markPending(now: now)
        XCTAssertEqual(state.nextDate, now.addingTimeInterval(3_600))
        let finished = now.addingTimeInterval(60)
        state.complete(token: token, now: finished)
        XCTAssertNil(state.pendingToken)
        XCTAssertNil(state.retryAt)
        XCTAssertEqual(state.nextDate, finished.addingTimeInterval(86_400))
    }

    func testNewDataDuringExportCannotBeClearedByItsCompletion() {
        var state = HealthWritebackScheduleState(now: now)
        let first = state.markPending(now: now)
        let next = state.markPending(now: now.addingTimeInterval(30))
        state.complete(token: first, now: now.addingTimeInterval(60))
        XCTAssertEqual(state.pendingToken, next)
        XCTAssertEqual(state.nextDate, now.addingTimeInterval(3_600), "new arrivals must not postpone the retry")
        state.complete(token: next, now: now.addingTimeInterval(90))
        XCTAssertNil(state.pendingToken)
    }

    func testInterruptedExportSurvivesRestartAndFailedOrHeldWorkRetries() throws {
        var state = HealthWritebackScheduleState(now: now)
        let token = state.markPending(now: now)
        let data = try PropertyListEncoder().encode(state)
        var restored = try PropertyListDecoder().decode(HealthWritebackScheduleState.self, from: data)
        XCTAssertEqual(restored, state)
        let retryTime = now.addingTimeInterval(3_600)
        restored.retryLater(now: retryTime)
        XCTAssertEqual(restored.pendingToken, token)
        XCTAssertEqual(restored.nextDate, retryTime.addingTimeInterval(3_600))
        restored.complete(token: token, now: retryTime.addingTimeInterval(60))
        XCTAssertNil(restored.pendingToken)
    }
}
