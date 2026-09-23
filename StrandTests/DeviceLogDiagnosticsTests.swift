import XCTest
import WhoopProtocol
@testable import Strand

final class DeviceLogDiagnosticsTests: XCTestCase {
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
