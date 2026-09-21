import XCTest
@testable import Strand

final class RealtimeCommandDeferralTests: XCTestCase {
    func testOpeningLiveDuringHistoryWaitsAndRestoresHRBeforeRaw() {
        var pending = RealtimeCommandDeferral()
        var wire: [RealtimeCommandDeferral.Command] = []
        pending.remember(.raw, enabled: true)
        pending.remember(.heartRate, enabled: true)
        XCTAssertTrue(wire.isEmpty, "opening Live must not send mode changes into a history transfer")
        wire += pending.takeCommands()
        XCTAssertEqual(wire, [.init(stream: .heartRate, enabled: true), .init(stream: .raw, enabled: true)])
        XCTAssertTrue(pending.takeCommands().isEmpty, "one completion cannot replay changes twice")
    }

    func testClosingLiveBeforeCompletionCancelsDeferredStart() {
        var pending = RealtimeCommandDeferral()
        pending.remember(.raw, enabled: true) // pre-sync stream to restore
        pending.remember(.heartRate, enabled: true)
        pending.remember(.raw, enabled: false)
        pending.remember(.heartRate, enabled: false)
        XCTAssertEqual(pending.takeCommands(), [.init(stream: .heartRate, enabled: false),
                                                .init(stream: .raw, enabled: false)])
    }

    func testMultipleScreenChangesApplyOnlyTheFinalIntent() {
        for toggles in [[true], [true, false], [true, false, true], [false, true, false]] {
            var pending = RealtimeCommandDeferral()
            for enabled in toggles {
                pending.remember(.heartRate, enabled: enabled)
                pending.remember(.raw, enabled: enabled)
            }
            XCTAssertEqual(pending.takeCommands(), [.init(stream: .heartRate, enabled: toggles.last!),
                                                    .init(stream: .raw, enabled: toggles.last!)])
        }
    }

    func testPassiveSyncDoesNotCreateLiveDemandAndDisconnectDropsPendingCommands() {
        var pending = RealtimeCommandDeferral()
        XCTAssertTrue(pending.takeCommands().isEmpty)
        pending.remember(.raw, enabled: true)
        pending = RealtimeCommandDeferral()
        XCTAssertTrue(pending.takeCommands().isEmpty)
    }
}
