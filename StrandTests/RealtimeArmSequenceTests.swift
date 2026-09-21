import XCTest
@testable import Strand

final class RealtimeArmSequenceTests: XCTestCase {
    func testFirstOpenLeavesBothRequestedStreamsArmedWithoutATimerTick() {
        var hrEnabled = false
        var rawEnabled = false
        RealtimeArmSequence.perform(enableHR: {
            hrEnabled = true
            rawEnabled = false // Observed firmware side effect of enabling HR.
        }, enableRaw: { rawEnabled = true })
        XCTAssertTrue(hrEnabled)
        XCTAssertTrue(rawEnabled, "the first HR enable must not cancel the live raw feed")
    }

    func testReconnectAndRepeatedRearmsPreserveRawFeed() {
        var rawEnabled = false
        for _ in 0..<3 {
            RealtimeArmSequence.perform(enableHR: { rawEnabled = false }, enableRaw: { rawEnabled = true })
            XCTAssertTrue(rawEnabled)
        }
    }
}
