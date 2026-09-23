import XCTest
@testable import Strand

final class HealthWritebackUnlockGateTests: XCTestCase {
    private let available = Notification.Name("HealthWritebackUnlockGateTests.available")

    @MainActor
    func testLockedImportsRetainWidestWindowThroughCoalescing() {
        let center = NotificationCenter()
        let gate = HealthWritebackUnlockGate(center: center, availableNotification: available)
        var window = HealthSyncRequestWindow()
        var imported: [Int] = []
        for days in [30, 7, 1] {
            window.request(days: days)
            XCTAssertTrue(gate.deferUntilAvailable(isAvailable: false) {
                imported.append(window.take(covering: days))
            })
        }
        center.post(name: available, object: nil)
        center.post(name: available, object: nil)
        XCTAssertEqual(imported, [30])
        XCTAssertNil(window.days)
    }

    func testForegroundImportConsumesPendingWindowWithoutNarrowingIt() {
        var window = HealthSyncRequestWindow()
        window.request(days: 90)
        window.request(days: 1)
        XCTAssertEqual(window.take(covering: 7), 90)
        XCTAssertNil(window.days)
        XCTAssertEqual(window.take(covering: 30), 30)
    }

    @MainActor
    func testManyLockedRequestsRetryOnceWithLatestWork() {
        let center = NotificationCenter()
        let gate = HealthWritebackUnlockGate(center: center, availableNotification: available)
        var writes: [Int] = []
        for revision in 1...100 {
            XCTAssertTrue(gate.deferUntilAvailable(isAvailable: false) { writes.append(revision) })
        }
        XCTAssertTrue(writes.isEmpty)
        center.post(name: available, object: nil)
        center.post(name: available, object: nil)
        XCTAssertEqual(writes, [100])
    }

    @MainActor
    func testForegroundWriteConsumesDebtBeforeDelayedUnlockNotification() {
        let center = NotificationCenter()
        let gate = HealthWritebackUnlockGate(center: center, availableNotification: available)
        var retries = 0
        XCTAssertTrue(gate.deferUntilAvailable(isAvailable: false) { retries += 1 })
        XCTAssertFalse(gate.deferUntilAvailable(isAvailable: true) { retries += 1 })
        center.post(name: available, object: nil)
        XCTAssertEqual(retries, 0)
    }

    @MainActor
    func testRelockDuringRetryCanWaitForNextUnlock() {
        let center = NotificationCenter()
        let gate = HealthWritebackUnlockGate(center: center, availableNotification: available)
        var retries = 0
        XCTAssertTrue(gate.deferUntilAvailable(isAvailable: false) {
            retries += 1
            XCTAssertTrue(gate.deferUntilAvailable(isAvailable: false) { retries += 1 })
        })
        center.post(name: available, object: nil)
        XCTAssertEqual(retries, 1)
        center.post(name: available, object: nil)
        center.post(name: available, object: nil)
        XCTAssertEqual(retries, 2)
    }

    @MainActor
    func testDestroyingGateDiscardsPendingRetry() {
        let center = NotificationCenter()
        var gate: HealthWritebackUnlockGate? = HealthWritebackUnlockGate(center: center, availableNotification: available)
        weak var weakGate = gate
        var retries = 0
        XCTAssertTrue(gate!.deferUntilAvailable(isAvailable: false) { retries += 1 })
        gate = nil
        XCTAssertNil(weakGate)
        center.post(name: available, object: nil)
        XCTAssertEqual(retries, 0)
    }
}
