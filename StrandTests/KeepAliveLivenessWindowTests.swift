import XCTest
@testable import Strand

final class KeepAliveLivenessWindowTests: XCTestCase {
    private func check(_ window: inout KeepAliveLivenessWindow, _ now: Double, lastData: Double) -> Bool {
        window.shouldReconnect(now: now, lastDataAt: lastData, silenceLimit: 120, expectedTickInterval: 30)
    }

    func testOvernightSuspensionDoesNotBounceBeforeBatteryPollCanReply() {
        var window = KeepAliveLivenessWindow()
        XCTAssertFalse(check(&window, 0, lastData: 0))
        XCTAssertFalse(check(&window, 30, lastData: 0))
        // Recorded overnight shape: the next keep-alive arrives about ten minutes later.
        XCTAssertFalse(check(&window, 610, lastData: 30))
        // Battery notification arrives after the resumed callback sends its existing poll.
        for now in stride(from: 640.0, through: 940.0, by: 30) {
            XCTAssertFalse(check(&window, now, lastData: now - 30))
        }
    }

    func testActuallyUnresponsiveConnectionStillRecovers() {
        var window = KeepAliveLivenessWindow()
        for now in stride(from: 600.0, through: 720.0, by: 30) {
            XCTAssertFalse(check(&window, now, lastData: 0))
        }
        XCTAssertTrue(check(&window, 750, lastData: 0))
    }

    func testRepeatedBackgroundGapsNeverBecomeEvidenceOfAnUnansweredPoll() {
        var window = KeepAliveLivenessWindow()
        for now in stride(from: 0.0, through: 28_800.0, by: 600) {
            XCTAssertFalse(check(&window, now, lastData: 0))
        }
    }

    func testReceivedDataRestartsSilenceWindow() {
        var window = KeepAliveLivenessWindow()
        for now in stride(from: 0.0, through: 120.0, by: 30) {
            XCTAssertFalse(check(&window, now, lastData: 0))
        }
        XCTAssertFalse(check(&window, 150, lastData: 140))
        for now in stride(from: 180.0, through: 240.0, by: 30) {
            XCTAssertFalse(check(&window, now, lastData: 140))
        }
        XCTAssertTrue(check(&window, 270, lastData: 140))
    }

    func testResetAndClockChangesStartANewObservationWindow() {
        var window = KeepAliveLivenessWindow()
        for now in stride(from: 0.0, through: 120.0, by: 30) {
            XCTAssertFalse(check(&window, now, lastData: 0))
        }
        window.reset()
        XCTAssertFalse(check(&window, 150, lastData: 0))
        XCTAssertFalse(check(&window, -3600, lastData: -4000))
        XCTAssertFalse(check(&window, 3600, lastData: 0))
    }

    func testOneDelayedTickIsToleratedButLongerGapRestartsGrace() {
        var window = KeepAliveLivenessWindow()
        XCTAssertFalse(check(&window, 0, lastData: 0))
        XCTAssertFalse(check(&window, 60, lastData: 0))
        XCTAssertFalse(check(&window, 120, lastData: 0))
        XCTAssertFalse(check(&window, 181, lastData: 0))
        XCTAssertFalse(check(&window, 211, lastData: 0))
    }
}
