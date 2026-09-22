import XCTest
@testable import StrandAnalytics

final class BackgroundWorkPolicyTests: XCTestCase {
    func testRSSIRelaxesOnlyForHealthyBackgroundLinks() {
        func due(_ elapsed: Double?, background: Bool = true, silent: Double = 0,
                 rssi: Int? = -60, detailed: Bool = false) -> Bool {
            BackgroundWorkPolicy.rssiDue(elapsed: elapsed, background: background, silentFor: silent,
                                         lastRSSI: rssi, detailedDiagnostics: detailed)
        }
        XCTAssertFalse(due(299))
        XCTAssertTrue(due(300))
        XCTAssertTrue(due(60, background: false))
        XCTAssertTrue(due(60, silent: 60))
        XCTAssertTrue(due(60, rssi: -90))
        XCTAssertTrue(due(60, rssi: nil))
        XCTAssertTrue(due(60, detailed: true))
        XCTAssertTrue(due(nil))
        XCTAssertTrue(due(-1))
    }

    func testHostPowerSavingNeverShortensAnExistingOffloadInterval() {
        XCTAssertEqual(BackgroundWorkPolicy.offloadInterval(base: 900, backgroundLowPower: true), 3600)
        XCTAssertEqual(BackgroundWorkPolicy.offloadInterval(base: 7200, backgroundLowPower: true), 7200)
        XCTAssertEqual(BackgroundWorkPolicy.offloadInterval(base: 900, backgroundLowPower: false), 900)
    }

    func testHeldNightAndVitalsSurviveUntilSourceCloses() {
        let existing = ["closed", "open"]
        let scoped = existing.filter { HealthExportScope.includes($0, holding: ["open"]) }
        XCTAssertEqual(ExportSampleDiff.plan(existing: scoped, desired: []).remove, [0])
        XCTAssertFalse(HealthExportScope.includes(200, holding: Set([200])))
        XCTAssertTrue(HealthExportScope.includes(100, holding: Set([200])))
        let closed = existing.filter { HealthExportScope.includes($0, holding: []) }
        XCTAssertEqual(ExportSampleDiff.plan(existing: closed, desired: []).remove, [0, 1])
    }

    func testActivityDeduplicatesButRenewsBeforeStaleDeadline() {
        XCTAssertFalse(BackgroundWorkPolicy.activityDue(elapsed: 59, changed: false, background: true))
        XCTAssertTrue(BackgroundWorkPolicy.activityDue(elapsed: 60, changed: false, background: true))
        XCTAssertFalse(BackgroundWorkPolicy.activityDue(elapsed: 14, changed: true, background: true))
        XCTAssertTrue(BackgroundWorkPolicy.activityDue(elapsed: 15, changed: true, background: true))
        XCTAssertTrue(BackgroundWorkPolicy.activityDue(elapsed: 2, changed: true, background: false))
    }
    func testSilentWhoop4KeepsLivenessProbeCadence() {
        XCTAssertTrue(BackgroundWorkPolicy.relaxedBatteryPolling(background: true, whoop4: true, silentFor: 59))
        XCTAssertFalse(BackgroundWorkPolicy.relaxedBatteryPolling(background: true, whoop4: true, silentFor: 60))
        XCTAssertTrue(BackgroundWorkPolicy.relaxedBatteryPolling(background: true, whoop4: false, silentFor: 60))
        XCTAssertFalse(BackgroundWorkPolicy.relaxedBatteryPolling(background: false, whoop4: false, silentFor: 0))
    }
    func testBatteryForegroundChargingAndClockRollback() {
        XCTAssertFalse(BackgroundWorkPolicy.batteryDue(elapsed: 299, background: true, charging: false))
        XCTAssertTrue(BackgroundWorkPolicy.batteryDue(elapsed: 300, background: true, charging: false))
        XCTAssertTrue(BackgroundWorkPolicy.batteryDue(elapsed: 60, background: false, charging: false))
        XCTAssertTrue(BackgroundWorkPolicy.batteryDue(elapsed: 30, background: true, charging: true))
        XCTAssertTrue(BackgroundWorkPolicy.batteryDue(elapsed: nil, background: true, charging: false))
        XCTAssertTrue(BackgroundWorkPolicy.batteryDue(elapsed: -1, background: true, charging: false))
    }

    func testExportRetryAfterPartialSaveDoesNotRewriteSuccessfulRecords() {
        let before = ["old-night", "unchanged", "old-HR-bucket"]
        let desired = ["corrected-night", "unchanged", "corrected-HR-bucket"]
        let first = ExportSampleDiff.plan(existing: before, desired: desired)
        XCTAssertEqual(first.remove, [0, 2])
        // Deletion succeeded, then the process stopped after saving the first replacement.
        let actualAfterFailure = ["unchanged", "corrected-night"]
        let retry = ExportSampleDiff.plan(existing: actualAfterFailure, desired: desired)
        XCTAssertEqual(retry.remove, [])
        XCTAssertEqual(retry.insert, [2])
        let complete = actualAfterFailure + retry.insert.map { desired[$0] }
        let final = ExportSampleDiff.plan(existing: complete, desired: desired)
        XCTAssertTrue(final.remove.isEmpty)
        XCTAssertTrue(final.insert.isEmpty)
    }

    func testExportDiffRepairsDuplicatesAndPreservesUnchangedRecords() {
        let diff = ExportSampleDiff.plan(existing: ["a", "a", "b", "old"], desired: ["a", "b", "corrected"])
        XCTAssertEqual(diff.remove, [1, 3])
        XCTAssertEqual(diff.insert, [2])
        let retry = ExportSampleDiff.plan(existing: ["a", "b"], desired: ["a", "b", "corrected"])
        XCTAssertEqual(retry.remove, [])
        XCTAssertEqual(retry.insert, [2])
        XCTAssertEqual(ExportSampleDiff.plan(existing: ["a"], desired: []).remove, [0])
    }
    func testExportPlanConvergesForEverySmallMultiset() {
        var inputs: [[String]] = [[]]
        var level: [[String]] = [[]]
        for _ in 0..<4 {
            level = level.flatMap { prefix in ["a", "b", "c"].map { prefix + [$0] } }
            inputs += level
        }
        for existing in inputs {
            for desired in inputs {
                let plan = ExportSampleDiff.plan(existing: existing, desired: desired)
                let removals = Set(plan.remove)
                let result = existing.enumerated().filter { !removals.contains($0.offset) }.map(\.element)
                    + plan.insert.map { desired[$0] }
                XCTAssertEqual(result.sorted(), desired.sorted())
                let retry = ExportSampleDiff.plan(existing: result, desired: desired)
                XCTAssertTrue(retry.remove.isEmpty && retry.insert.isEmpty)
            }
        }
    }

    func testUnchangedTwoWeeksNeedNoWrites() {
        let samples = (0..<(14 * 1440)).map { "minute-\($0):75bpm" }
        let plan = ExportSampleDiff.plan(existing: samples, desired: samples)
        XCTAssertTrue(plan.remove.isEmpty && plan.insert.isEmpty)
        XCTAssertTrue(BackgroundWorkPolicy.activityDue(elapsed: -1, changed: false, background: true))
        XCTAssertFalse(BackgroundWorkPolicy.activityDue(elapsed: 1.99, changed: true, background: false))
    }

}
