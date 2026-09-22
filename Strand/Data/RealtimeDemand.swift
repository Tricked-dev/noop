import Foundation

/// Display requests survive navigation and suspension independently of recording sessions.
/// Continuous HRV capture remains a separate demand owned by BLEManager.
struct RealtimeDemand {
    enum Session: Hashable { case workout, liveCoaching, lifting }

    private(set) var screens = 0
    private(set) var sessions = Set<Session>()
    var isBackground = false

    var wantsStream: Bool { (!isBackground && screens > 0) || !sessions.isEmpty }

    mutating func addScreen() { screens += 1 }
    mutating func removeScreen() { screens = max(0, screens - 1) }
    mutating func setSession(_ session: Session, active: Bool) {
        if active { sessions.insert(session) } else { sessions.remove(session) }
    }
}
