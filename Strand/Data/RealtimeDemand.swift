import Foundation

/// Display requests survive navigation and suspension independently of recording sessions.
/// Continuous HRV capture remains a separate demand owned by BLEManager.
struct RealtimeDemand {
    enum Session: Hashable { case workout, liveCoaching, lifting, liveActivity }

    private(set) var screens = 0
    private(set) var sessions = Set<Session>()
    var isBackground = false

    var wantsStream: Bool { (!isBackground && screens > 0) || sessions.contains { $0 != .liveActivity } }
    var wantsLightweightHR: Bool { sessions.contains(.liveActivity) }

    mutating func addScreen() { screens += 1 }
    mutating func removeScreen() { screens = max(0, screens - 1) }
    mutating func setSession(_ session: Session, active: Bool) {
        if active { sessions.insert(session) } else { sessions.remove(session) }
    }
}

/// A Live screen owns one request while showing a WHOOP, even before the link is ready.
/// Connection callbacks may re-arm that request but must never acquire another one.
struct LiveScreenRealtimeRequest {
    private(set) var isVisible = false
    private(set) var isRequested = false

    mutating func update(visible: Bool, isWhoop: Bool, setRequested: (Bool) -> Void) {
        isVisible = visible
        let wanted = visible && isWhoop
        guard wanted != isRequested else { return }
        isRequested = wanted
        setRequested(wanted)
    }
}

/// Short WHOOP 4 raw samples refresh a banner when its standard HR characteristic stays silent.
/// The raw stream must be stopped after a sample or the timeout, never held by the banner.
enum LiveActivityRawProbePolicy {
    static let maxDuration: TimeInterval = 4
    static let minimumInterval: TimeInterval = 25

    static func shouldStart(now: Date, lastStart: Date?, banner: Bool, fullStream: Bool,
                            connected: Bool, whoop4: Bool, fallback: Bool, backfilling: Bool,
                            alreadyRunning: Bool) -> Bool {
        banner && !fullStream && connected && whoop4 && !fallback && !backfilling && !alreadyRunning
            && (lastStart.map { now.timeIntervalSince($0) >= minimumInterval } ?? true)
    }
}
