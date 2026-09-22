import XCTest
@testable import Strand
import WhoopStore

final class RealtimeDemandTests: XCTestCase {
    func testLockAndUnlockPreserveVisibleOwnersWithoutKeepingStreamOpen() {
        var demand = RealtimeDemand()
        demand.addScreen()
        demand.addScreen()
        XCTAssertTrue(demand.wantsStream)
        demand.isBackground = true
        XCTAssertFalse(demand.wantsStream)
        demand.removeScreen() // A sheet disappears while already backgrounded.
        demand.isBackground = false
        XCTAssertTrue(demand.wantsStream)
        demand.removeScreen()
        XCTAssertFalse(demand.wantsStream)
        demand.removeScreen() // A duplicate disappearance cannot make the next owner negative.
        demand.addScreen()
        XCTAssertTrue(demand.wantsStream)
    }

    func testRecordingOutlivesScreensAndOtherSessions() {
        var demand = RealtimeDemand()
        demand.addScreen()
        demand.setSession(.workout, active: true)
        demand.setSession(.liveCoaching, active: true)
        demand.setSession(.workout, active: true) // Restoring the same session is idempotent.
        demand.isBackground = true
        demand.removeScreen()
        XCTAssertTrue(demand.wantsStream)
        demand.setSession(.workout, active: false)
        XCTAssertTrue(demand.wantsStream)
        demand.setSession(.liveCoaching, active: false)
        XCTAssertFalse(demand.wantsStream)
    }

    func testColdBackgroundLaunchDoesNotArmARecreatedScreen() {
        var demand = RealtimeDemand()
        demand.isBackground = true
        demand.addScreen()
        XCTAssertFalse(demand.wantsStream)
        demand.setSession(.workout, active: true)
        XCTAssertTrue(demand.wantsStream)
    }

    @MainActor
    func testLiftControllerReleasesRecordingDemandOnFinishAndDiscard() {
        var requests: [Bool] = []
        let controller = LiftSessionController(buzz: { _ in }, setStrapHandler: { _ in },
                                              setRealtimeDemand: { requests.append($0) })
        let plan = [LiftPlanItem(exercise: "Bench", primaryMuscle: .chest, targetSets: 2, restSec: 60)]
        controller.start(plan: plan, programId: nil, programName: nil)
        controller.advance()
        controller.advance()
        XCTAssertEqual(requests, [true], "per-set changes must not add extra owners")
        controller.finish()
        XCTAssertEqual(requests, [true, false])
        controller.discard()
        XCTAssertEqual(requests, [true, false], "cleanup after finish must not release a second owner")
        controller.start(plan: plan, programId: nil, programName: nil)
        controller.discard()
        XCTAssertEqual(requests, [true, false, true, false])
    }
}
