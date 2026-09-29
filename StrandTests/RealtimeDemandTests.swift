import XCTest
@testable import Strand
import WhoopStore

final class RealtimeDemandTests: XCTestCase {
    func testLiveScreenRequestsBeforeConnectionAndReleasesOnlyItsOwnRequest() {
        var screen = LiveScreenRealtimeRequest()
        var demand = RealtimeDemand()
        demand.addScreen() // Another live display already owns a request.
        var transitions: [Bool] = []
        func update(visible: Bool, isWhoop: Bool) {
            screen.update(visible: visible, isWhoop: isWhoop) { requested in
                transitions.append(requested)
                if requested { demand.addScreen() } else { demand.removeScreen() }
            }
        }

        // Appearing before discovery/bonding still registers intent for the post-bond arm.
        update(visible: true, isWhoop: true)
        XCTAssertEqual(demand.screens, 2)
        XCTAssertTrue(demand.wantsStream)
        update(visible: true, isWhoop: true) // Repeated lifecycle delivery cannot leak an owner.
        XCTAssertEqual(demand.screens, 2)
        demand.isBackground = true
        XCTAssertFalse(demand.wantsStream)
        demand.isBackground = false
        XCTAssertTrue(demand.wantsStream)
        update(visible: false, isWhoop: true)
        update(visible: false, isWhoop: true)
        XCTAssertEqual(demand.screens, 1)
        XCTAssertEqual(transitions, [true, false])
    }

    func testSwitchingLiveDeviceBalancesOnlyTheWhoopRequest() {
        var screen = LiveScreenRealtimeRequest()
        var transitions: [Bool] = []
        func update(visible: Bool, isWhoop: Bool) {
            screen.update(visible: visible, isWhoop: isWhoop) { transitions.append($0) }
        }
        update(visible: true, isWhoop: false)
        update(visible: false, isWhoop: false)
        XCTAssertEqual(transitions, [], "A ring screen must not release another screen's request")
        update(visible: true, isWhoop: false)
        update(visible: true, isWhoop: true)
        update(visible: true, isWhoop: false)
        update(visible: true, isWhoop: true)
        update(visible: false, isWhoop: true)
        XCTAssertEqual(transitions, [true, false, true, false])
        XCTAssertFalse(screen.isRequested)
        XCTAssertFalse(screen.isVisible)
    }

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

    func testLiveActivityKeepsStreamWhenPhoneLocksAndReleasesOnDismissal() {
        var demand = RealtimeDemand()
        demand.addScreen()
        demand.setSession(.liveActivity, active: true)
        demand.isBackground = true
        XCTAssertFalse(demand.wantsStream)
        XCTAssertTrue(demand.wantsLightweightHR)
        demand.removeScreen()
        XCTAssertFalse(demand.wantsStream)
        XCTAssertTrue(demand.wantsLightweightHR)
        demand.setSession(.liveActivity, active: false)
        XCTAssertFalse(demand.wantsStream)
        XCTAssertFalse(demand.wantsLightweightHR)
    }

    func testBannerRawProbeIsBoundedAndCannotReplaceFullOrUnhealthyStreaming() {
        let now = Date(timeIntervalSince1970: 1_000)
        func due(_ last: Date? = nil, banner: Bool = true, full: Bool = false,
                 connected: Bool = true, fallback: Bool = false, backfilling: Bool = false,
                 running: Bool = false) -> Bool {
            LiveActivityRawProbePolicy.shouldStart(now: now, lastStart: last, banner: banner,
                fullStream: full, connected: connected, whoop4: true, fallback: fallback,
                backfilling: backfilling, alreadyRunning: running)
        }
        XCTAssertTrue(due())
        XCTAssertFalse(due(now.addingTimeInterval(-24)))
        XCTAssertTrue(due(now.addingTimeInterval(-25)))
        XCTAssertFalse(due(banner: false))
        XCTAssertFalse(due(full: true))
        XCTAssertFalse(due(connected: false))
        XCTAssertFalse(due(fallback: true))
        XCTAssertFalse(due(backfilling: true))
        XCTAssertFalse(due(running: true))
        XCTAssertFalse(LiveActivityRawProbePolicy.shouldStart(now: now, lastStart: nil,
            banner: true, fullStream: false, connected: true, whoop4: false, fallback: false,
            backfilling: false, alreadyRunning: false))
        XCTAssertEqual(LiveActivityRawProbePolicy.maxDuration, 4)
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
