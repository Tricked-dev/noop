import XCTest
@testable import Strand

final class NotificationRestoreTrackerTests: XCTestCase {
    func testDiscoveryAndPostBondCannotQueueTwoOffOnCycles() {
        var tracker = NotificationRestoreTracker<String>()
        let channels = ["command", "event", "data", "hr", "battery"]
        for channel in channels { XCTAssertTrue(tracker.request(channel)) }
        for channel in channels { XCTAssertFalse(tracker.request(channel)) }
        tracker.confirmed("command")
        XCTAssertTrue(tracker.hasPending(in: ["command", "event", "data"]))
        tracker.confirmed("event")
        XCTAssertTrue(tracker.hasPending(in: ["command", "event", "data"]))
        tracker.confirmed("data")
        XCTAssertFalse(tracker.hasPending(in: ["command", "event", "data"]))
        XCTAssertTrue(tracker.hasPending(in: ["hr", "battery"]))
        XCTAssertFalse(tracker.request("data"), "confirmation must not rearm another off/on cycle")
    }

    func testFailureAllowsRetryButCannotReleaseSyncEarly() {
        var tracker = NotificationRestoreTracker<String>()
        XCTAssertTrue(tracker.request("data"))
        tracker.failed("data")
        XCTAssertTrue(tracker.hasPending(in: ["data"]))
        XCTAssertTrue(tracker.request("data"))
        tracker.confirmed("data")
        XCTAssertFalse(tracker.hasPending(in: ["data"]))
    }

    func testFreshConnectionHasNoInheritedPendingSubscriptions() {
        var tracker = NotificationRestoreTracker<String>()
        _ = tracker.request("data")
        tracker = NotificationRestoreTracker()
        XCTAssertFalse(tracker.hasPending(in: ["data"]))
        XCTAssertTrue(tracker.request("data"))
    }
}
