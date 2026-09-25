import XCTest
import WhoopProtocol
@testable import Strand

final class DeviceLogDiagnosticsTests: XCTestCase {
    func testRepeatedSyncDeferralsAreCoalescedWithoutHidingOtherReasons() {
        var gate = SyncDeferralLogGate()
        XCTAssertEqual(gate.suppressedCountToEmit(trigger: .strap, reason: "recent-sync cooldown", now: 100), 0)
        XCTAssertNil(gate.suppressedCountToEmit(trigger: .strap, reason: "recent-sync cooldown", now: 101))
        XCTAssertEqual(gate.suppressedCountToEmit(trigger: .foreground, reason: "recent-sync cooldown", now: 102), 0)
        XCTAssertEqual(gate.suppressedCountToEmit(trigger: .strap, reason: "stalled-transfer cooldown", now: 103), 0)
        XCTAssertNil(gate.suppressedCountToEmit(trigger: .strap, reason: "recent-sync cooldown", now: 159))
        XCTAssertEqual(gate.suppressedCountToEmit(trigger: .strap, reason: "recent-sync cooldown", now: 160), 2)
        XCTAssertEqual(gate.suppressedCountToEmit(trigger: .strap, reason: "recent-sync cooldown", now: 220), 0)
    }

    func testDeferralLogClockResetDoesNotSilenceFutureEvents() {
        var gate = SyncDeferralLogGate()
        XCTAssertEqual(gate.suppressedCountToEmit(trigger: .strap, reason: "cooldown", now: 100), 0)
        XCTAssertNil(gate.suppressedCountToEmit(trigger: .strap, reason: "cooldown", now: 101))
        XCTAssertEqual(gate.suppressedCountToEmit(trigger: .strap, reason: "cooldown", now: 10), 1)
    }

    func testSleepEvidenceSeparatesInputCutoffFromDetectedEnd() {
        let line = DeviceLogDiagnostics.sleepBoundaryLine(day: "2025-01-02", readEnd: 9000,
            hrCount: 300, hrLast: 7200, motionCount: 250, motionLast: 7100,
            sessions: [(3600, 6900)])
        XCTAssertEqual(line, "sleep-boundary day=2025-01-02 readEnd=9000 hr=300 hrLast=7200 motion=250 motionLast=7100 sessions=1 bounds=[3600:6900] truncated=false")
        let missing = DeviceLogDiagnostics.sleepBoundaryLine(day: "2025-01-02", readEnd: 9000,
            hrCount: 0, hrLast: nil, motionCount: 0, motionLast: nil, sessions: [])
        XCTAssertTrue(missing.contains("hrLast=none"))
        XCTAssertTrue(missing.contains("motionLast=none sessions=0 bounds=[]"))
        let many = DeviceLogDiagnostics.sleepBoundaryLine(day: "2025-01-02", readEnd: 9000,
            hrCount: 300, hrLast: 7200, motionCount: 250, motionLast: 7100,
            sessions: (0..<100).map { ($0, $0 + 1) })
        XCTAssertTrue(many.contains("sessions=100"))
        XCTAssertTrue(many.hasSuffix("truncated=true"))
        XCTAssertLessThan(many.count, 300)
    }

    func testConsoleControlsCannotSplitLinesOrMakeTheArchiveBinary() {
        XCTAssertEqual(DeviceLogDiagnostics.consoleFragment("a\0b\n\r\t\\n\u{85}"),
                       "a\\u{0000}b\\n\\r\\t\\\\n\\u{0085}")
        XCTAssertEqual(DeviceLogDiagnostics.consoleFragment("café 💚"), "café 💚")
        XCTAssertEqual(DeviceLogDiagnostics.consoleFragment(String(repeating: "x", count: 301)),
                       String(repeating: "x", count: 300) + " [fragment truncated]")
    }

    func testValidRecordWithoutUsableSignalsIsNotCalledACRCFailure() {
        let frame = ParsedFrame(ok: true, typeName: "HISTORICAL_DATA", seq: nil, cmdName: nil,
            crcOK: true, lenBytes: 84, rawHex: "", fields: [], parsed: ["unix": .int(1_700_000_000)])
        XCTAssertEqual(DeviceLogDiagnostics.rejectionReason(frame, unmapped: false), "no-usable-hr-or-motion")
        XCTAssertEqual(DeviceLogDiagnostics.rejectionReason(frame, unmapped: true), "unmapped-layout")
        let missingTime = ParsedFrame(ok: true, typeName: "HISTORICAL_DATA", seq: nil, cmdName: nil,
            crcOK: true, lenBytes: 84, rawHex: "", fields: [], parsed: [:])
        XCTAssertEqual(DeviceLogDiagnostics.rejectionReason(missingTime, unmapped: false), "missing-timestamp")
    }

    func testCooldownReasonMatchesTheGateIncludingManualBypass() {
        XCTAssertEqual(BackfillPolicy.phoneDeferralReason(trigger: .foreground, now: 1000,
            lastAttempt: 999, lastCompleted: nil, retryAfter: 1100), "stalled-transfer cooldown")
        XCTAssertEqual(BackfillPolicy.phoneDeferralReason(trigger: .strap, now: 1000,
            lastAttempt: 999, lastCompleted: nil, retryAfter: 999), "recent-sync cooldown")
        for trigger: BackfillTrigger in [.manual, .connect, .foreground, .strap, .periodic, .autoContinue] {
            for retry: Double? in [nil, 900, 1100] {
                XCTAssertEqual(BackfillPolicy.phoneAllows(trigger: trigger, now: 1000,
                    lastAttempt: 999, lastCompleted: nil, retryAfter: retry),
                    BackfillPolicy.phoneDeferralReason(trigger: trigger, now: 1000,
                        lastAttempt: 999, lastCompleted: nil, retryAfter: retry) == nil)
            }
        }
    }
}
