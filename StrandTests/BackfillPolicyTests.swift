import XCTest
@testable import Strand

/// `BackfillPolicy` rate-limiter, incl. the empty-streak backoff that stops an off-wrist / not-banking
/// strap from being re-offloaded every event floor (#77/#120/#216). Pure value logic, no CoreBluetooth seam.
final class BackfillPolicyTests: XCTestCase {
    func testCompletedFreshHistoryDoesNotStartAnotherOffload() {
        let now = 1_790_021_129
        for lag in [0, 6, 299, 300] {
            XCTAssertFalse(BackfillPolicy.phoneAllowsContinuation(completed: true, now: now,
                                                                  frontier: now - lag))
        }
    }

    func testDeepOrUnknownBacklogRetainsContinuation() {
        let now = 1_790_021_129
        for frontier: Int? in [nil, 0, now - 301, now - 3600, now - 86400] {
            XCTAssertTrue(BackfillPolicy.phoneAllowsContinuation(completed: true, now: now,
                                                                 frontier: frontier))
        }
    }

    func testTimeoutDoesNotPretendTheOffloadCompleted() {
        XCTAssertTrue(BackfillPolicy.phoneAllowsContinuation(completed: false, now: 1_000,
                                                             frontier: 999))
    }

    func testFutureFrontierCannotCreateAnImmediateRetryLoop() {
        XCTAssertFalse(BackfillPolicy.phoneAllowsContinuation(completed: true, now: 1_000,
                                                              frontier: 1_100))
    }

    func testRoutineEventsCannotPostponeAStalledTransfersDeadline() {
        var deadline = 60.0
        for elapsed in stride(from: 0.0, through: 600.0, by: 20.0) {
            if BackfillPolicy.extendsIdleTimeout(packetType: 48, frameIsValid: true) {
                deadline = elapsed + 60
            }
        }
        XCTAssertEqual(deadline, 60, "live events used to keep this session open indefinitely")
    }

    func testCorruptFramesNeverExtendTheDeadlineRegardlessOfClaimedType() {
        for type in UInt8.min...UInt8.max {
            XCTAssertFalse(BackfillPolicy.extendsIdleTimeout(packetType: type, frameIsValid: false))
        }
    }

    func testSlowButProductiveHistoryStillExtendsTheDeadline() {
        var deadline = 60.0
        for (elapsed, type): (Double, UInt8) in [(45, 49), (90, 47), (135, 50), (180, 56)] {
            XCTAssertLessThan(elapsed, deadline)
            if BackfillPolicy.extendsIdleTimeout(packetType: type, frameIsValid: true) {
                deadline = elapsed + 60
            }
        }
        XCTAssertEqual(deadline, 240)
        for type: UInt8 in [35, 36, 40, 43, 48] {
            XCTAssertFalse(BackfillPolicy.extendsIdleTimeout(packetType: type, frameIsValid: true))
        }
    }

    private let fe = BackfillPolicy.eventFloorSeconds      // 90
    private let fp = BackfillPolicy.periodicFloorSeconds   // 900

    func testPhonePowerSavingDelaysAutomaticSyncButPreservesExplicitAndOngoingWork() {
        for trigger in [BackfillTrigger.periodic, .strap] {
            XCTAssertFalse(BackfillPolicy.shouldRun(trigger: trigger, now: 3599, lastBackfillAt: 0,
                                                    backgroundLowPower: true))
            XCTAssertTrue(BackfillPolicy.shouldRun(trigger: trigger, now: 3600, lastBackfillAt: 0,
                                                   backgroundLowPower: true))
            XCTAssertTrue(BackfillPolicy.shouldRun(trigger: trigger, now: 3600, lastBackfillAt: nil,
                                                   backgroundLowPower: true))
        }
        for trigger in [BackfillTrigger.manual, .autoContinue] {
            XCTAssertTrue(BackfillPolicy.shouldRun(trigger: trigger, now: 1, lastBackfillAt: 0,
                                                   backgroundLowPower: true))
        }
        for trigger in [BackfillTrigger.connect, .foreground] {
            XCTAssertTrue(BackfillPolicy.shouldRun(trigger: trigger, now: 90, lastBackfillAt: 0,
                                                   backgroundLowPower: true))
        }
    }

    func testUserStopBlocksAllAutomaticTriggersEvenWithoutPreviousSyncStamp() {
        for trigger in [BackfillTrigger.periodic, .strap, .connect, .foreground, .autoContinue] {
            for last: Double? in [nil, 0] {
                XCTAssertFalse(BackfillPolicy.shouldRun(trigger: trigger, now: 1047, lastBackfillAt: last,
                                                        userPausedUntil: 1900))
            }
        }
    }

    func testManualSyncResumesDuringUserPauseAndAutomaticSyncReturnsAtDeadline() {
        XCTAssertTrue(BackfillPolicy.shouldRun(trigger: .manual, now: 1047, lastBackfillAt: 1046,
                                               userPausedUntil: 1900))
        for trigger in [BackfillTrigger.periodic, .strap, .connect, .foreground, .autoContinue] {
            XCTAssertFalse(BackfillPolicy.shouldRun(trigger: trigger, now: 1899, lastBackfillAt: 0,
                                                    userPausedUntil: 1900))
            XCTAssertTrue(BackfillPolicy.shouldRun(trigger: trigger, now: 1900, lastBackfillAt: 0,
                                                   userPausedUntil: 1900))
        }
        XCTAssertNotEqual(BackfillPolicy.userPauseKey(deviceId: "strap-A"),
                          BackfillPolicy.userPauseKey(deviceId: "strap-B"))
        XCTAssertEqual(BackfillPolicy.userPauseSeconds, 900)
    }

    func testUserPauseDoesNotReplaceExistingClockOrRateLimits() {
        XCTAssertFalse(BackfillPolicy.shouldRun(trigger: .periodic, now: 1900, lastBackfillAt: 1899,
                                                userPausedUntil: 1900))
        XCTAssertFalse(BackfillPolicy.shouldRun(trigger: .strap, now: 1900, lastBackfillAt: 0,
                                                clockUntrusted: true, userPausedUntil: 1900))
    }

    func testPhoneForegroundWaitsFromLatestCompletionAndManualStillRuns() {
        for elapsed in [0.0, 90, 899] {
            XCTAssertFalse(BackfillPolicy.phoneAllows(trigger: .foreground, now: 1000 + elapsed,
                lastAttempt: 900, lastCompleted: 1000, retryAfter: nil))
        }
        XCTAssertTrue(BackfillPolicy.phoneAllows(trigger: .foreground, now: 1900,
            lastAttempt: 900, lastCompleted: 1000, retryAfter: nil))
        XCTAssertTrue(BackfillPolicy.phoneAllows(trigger: .foreground, now: 1000,
            lastAttempt: nil, lastCompleted: nil, retryAfter: nil))
        XCTAssertTrue(BackfillPolicy.phoneAllows(trigger: .manual, now: 1001,
            lastAttempt: 900, lastCompleted: 1000, retryAfter: 2000))
    }

    func testSuspendedTimeoutCannotImmediatelyRestartOnAnyAutomaticTrigger() {
        // Phone log: requested at 20:58, timeout finally executes six minutes later on resume.
        for trigger in [BackfillTrigger.foreground, .connect, .strap, .periodic, .autoContinue] {
            XCTAssertFalse(BackfillPolicy.phoneAllows(trigger: trigger, now: 1361,
                lastAttempt: 1000, lastCompleted: nil, retryAfter: 1540))
        }
        XCTAssertTrue(BackfillPolicy.phoneAllows(trigger: .connect, now: 1540,
            lastAttempt: 1000, lastCompleted: nil, retryAfter: 1540))
        XCTAssertNotEqual(BackfillPolicy.retryKey(deviceId: "A"), BackfillPolicy.retryKey(deviceId: "B"))
    }

    func testRoutineStrapEventsCannotTurnBatteryNotificationsIntoNinetySecondSyncs() {
        for elapsed in [90.0, 180, 360, 899] {
            XCTAssertFalse(BackfillPolicy.phoneAllows(trigger: .strap, now: 1000 + elapsed,
                lastAttempt: 900, lastCompleted: 1000, retryAfter: nil))
        }
        XCTAssertTrue(BackfillPolicy.phoneAllows(trigger: .strap, now: 1900,
            lastAttempt: 900, lastCompleted: 1000, retryAfter: nil))
        // A productive backlog continues immediately; the event floor does not interrupt its drain.
        XCTAssertTrue(BackfillPolicy.phoneAllows(trigger: .autoContinue, now: 1001,
            lastAttempt: 900, lastCompleted: 1000, retryAfter: nil))
    }

    func testFirstSyncAlwaysRuns() {
        XCTAssertTrue(BackfillPolicy.shouldRun(trigger: .periodic, now: 1000, lastBackfillAt: nil))
        XCTAssertTrue(BackfillPolicy.shouldRun(trigger: .strap, now: 1000, lastBackfillAt: nil))
    }

    func testManualAlwaysRunsRegardlessOfFloorOrStreak() {
        XCTAssertTrue(BackfillPolicy.shouldRun(trigger: .manual, now: 1000, lastBackfillAt: 999, emptyStreak: 99))
    }

    // #364: the expedited auto-continue is deliberately un-floored like .manual — it must run even
    // immediately after the previous backfill (a 60s session just ended). Its runaway protection lives in
    // BLEManager's consecutive-cap + trim spin-detector, NOT in this policy, so the floor must NOT block it.
    func testAutoContinueAlwaysRunsRegardlessOfFloorOrStreak() {
        XCTAssertTrue(BackfillPolicy.shouldRun(trigger: .autoContinue, now: 1000, lastBackfillAt: 999, emptyStreak: 99))
        XCTAssertTrue(BackfillPolicy.shouldRun(trigger: .autoContinue, now: 1000, lastBackfillAt: 1000))
    }

    func testBaselineFloors() {
        XCTAssertFalse(BackfillPolicy.shouldRun(trigger: .strap, now: 1000, lastBackfillAt: 1000 - fe + 1))
        XCTAssertTrue (BackfillPolicy.shouldRun(trigger: .strap, now: 1000, lastBackfillAt: 1000 - fe))
        XCTAssertFalse(BackfillPolicy.shouldRun(trigger: .periodic, now: 10000, lastBackfillAt: 10000 - fp + 1))
        XCTAssertTrue (BackfillPolicy.shouldRun(trigger: .periodic, now: 10000, lastBackfillAt: 10000 - fp))
    }

    func testEmptyStreakBacksOffStrap() {
        // 200s elapsed: passes at baseline (floor 90), blocked once the 4x cap applies (floor 360).
        let last = 1000.0 - 200
        XCTAssertTrue (BackfillPolicy.shouldRun(trigger: .strap, now: 1000, lastBackfillAt: last, emptyStreak: 0))
        XCTAssertFalse(BackfillPolicy.shouldRun(trigger: .strap, now: 1000, lastBackfillAt: last, emptyStreak: 5))
    }

    func testBackoffIsGraduatedThenCapped() {
        // streak 3 → 2x floor (180s): 100s elapsed passes at baseline, blocked at 2x.
        let last = 1000.0 - 100
        XCTAssertTrue (BackfillPolicy.shouldRun(trigger: .strap, now: 1000, lastBackfillAt: last, emptyStreak: 0))
        XCTAssertFalse(BackfillPolicy.shouldRun(trigger: .strap, now: 1000, lastBackfillAt: last, emptyStreak: 3))
        // cap holds: a huge streak never stretches beyond 4x (floor 360); 360s elapsed still passes.
        XCTAssertTrue (BackfillPolicy.shouldRun(trigger: .strap, now: 1000, lastBackfillAt: 1000 - fe * 4, emptyStreak: 99))
    }

    func testBackoffNeverDelaysConnectOrForeground() {
        let last = 1000 - fe   // exactly at the baseline event floor
        XCTAssertTrue(BackfillPolicy.shouldRun(trigger: .connect, now: 1000, lastBackfillAt: last, emptyStreak: 99))
        XCTAssertTrue(BackfillPolicy.shouldRun(trigger: .foreground, now: 1000, lastBackfillAt: last, emptyStreak: 99))
    }

    // MARK: - #160: future-dated clock backoff

    /// #160: a future-dated-clock strap's recurring automatic offloads are SKIPPED ENTIRELY (not just
    /// throttled) — each ~60s offload starves the WHOOP4 realtime-HR re-arm, and #1012 won't trust the
    /// range anyway. `.strap` never runs while `clockUntrusted`, no matter how long since the last pass.
    func testClockUntrustedSkipsStrapEntirely() {
        // A huge elapsed that would trivially pass every floor: still skipped when the clock is untrusted.
        XCTAssertTrue (BackfillPolicy.shouldRun(trigger: .strap, now: 1_000_000, lastBackfillAt: 0,
                                                emptyStreak: 0, clockUntrusted: false))
        XCTAssertFalse(BackfillPolicy.shouldRun(trigger: .strap, now: 1_000_000, lastBackfillAt: 0,
                                                emptyStreak: 0, clockUntrusted: true))
    }

    func testClockUntrustedSkipsPeriodicEntirely() {
        XCTAssertTrue (BackfillPolicy.shouldRun(trigger: .periodic, now: 1_000_000, lastBackfillAt: 0,
                                                clockUntrusted: false))
        XCTAssertFalse(BackfillPolicy.shouldRun(trigger: .periodic, now: 1_000_000, lastBackfillAt: 0,
                                                clockUntrusted: true))
    }

    /// The skip is independent of `emptyStreak`: a clock-untrusted strap that is ALSO banking real rows
    /// (emptyStreak 0) is skipped just the same as one with a long empty streak.
    func testClockUntrustedSkipRegardlessOfEmptyStreak() {
        XCTAssertFalse(BackfillPolicy.shouldRun(trigger: .strap, now: 1_000_000, lastBackfillAt: 0,
                                                emptyStreak: 0, clockUntrusted: true))
        XCTAssertFalse(BackfillPolicy.shouldRun(trigger: .periodic, now: 1_000_000, lastBackfillAt: 0,
                                                emptyStreak: 99, clockUntrusted: true))
    }

    /// clockUntrusted must never delay a user- or connection-driven sync — the .connect pass is exactly
    /// how a self-corrected clock gets picked up again after the automatic triggers were skipped.
    func testClockUntrustedNeverDelaysConnectForegroundManualOrAutoContinue() {
        let last = 1000 - fe
        XCTAssertTrue(BackfillPolicy.shouldRun(trigger: .connect, now: 1000, lastBackfillAt: last, clockUntrusted: true))
        XCTAssertTrue(BackfillPolicy.shouldRun(trigger: .foreground, now: 1000, lastBackfillAt: last, clockUntrusted: true))
        XCTAssertTrue(BackfillPolicy.shouldRun(trigger: .manual, now: 1000, lastBackfillAt: 999, clockUntrusted: true))
        XCTAssertTrue(BackfillPolicy.shouldRun(trigger: .autoContinue, now: 1000, lastBackfillAt: 999, clockUntrusted: true))
    }
}
