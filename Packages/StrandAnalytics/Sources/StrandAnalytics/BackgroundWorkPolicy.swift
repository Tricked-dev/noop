import Foundation

/// Scheduling policy only; does not change sensor acquisition or connection deadlines.
public enum BackgroundWorkPolicy {
    /// Preserve diagnostic resolution on a quiet or weak link; healthy background links need
    /// fewer RSSI reads. This never changes the liveness watchdog or notification subscriptions.
    public static func rssiDue(elapsed: TimeInterval?, background: Bool, silentFor: TimeInterval,
                               lastRSSI: Int?, detailedDiagnostics: Bool) -> Bool {
        guard let elapsed, elapsed >= 0 else { return true }
        let stable = silentFor < 60 && (lastRSSI.map { $0 >= -80 } ?? false)
        return elapsed >= (background && stable && !detailedDiagnostics ? 300 : 60)
    }

    public static func offloadInterval(base: Int, backgroundLowPower: Bool) -> Int {
        backgroundLowPower ? max(base, 3_600) : base
    }

    public static func activityDue(elapsed: TimeInterval, changed: Bool, background: Bool) -> Bool {
        if elapsed < 0 { return true }
        return elapsed >= 60 || (changed && elapsed >= (background ? 15 : 2))
    }

    /// A quiet WHOOP 4 link still needs its original battery probe before the 120-second
    /// watchdog deadline. Slowing that probe could otherwise manufacture reconnects.
    public static func relaxedBatteryPolling(background: Bool, whoop4: Bool, silentFor: TimeInterval) -> Bool {
        background && (!whoop4 || silentFor < 60)
    }

    public static func batteryDue(elapsed: TimeInterval?, background: Bool, charging: Bool) -> Bool {
        guard let elapsed, elapsed >= 0 else { return true }
        return elapsed >= (charging ? 30 : (background ? 300 : 60))
    }
}

/// Multiset reconciliation against the destination's actual contents. A failed save or a
/// process restart needs no cursor repair: the next read naturally plans the missing records.
public enum ExportSampleDiff {
    public struct Plan: Equatable {
        public let remove: [Int]
        public let insert: [Int]
    }

    public static func plan(existing: [String], desired: [String]) -> Plan {
        var available: [String: [Int]] = [:]
        for (index, key) in desired.enumerated() { available[key, default: []].append(index) }
        var used: [String: Int] = [:]
        var kept = Set<Int>()
        var remove: [Int] = []
        for (index, key) in existing.enumerated() {
            let offset = used[key, default: 0]
            if let indices = available[key], offset < indices.count {
                kept.insert(indices[offset])
                used[key] = offset + 1
            } else { remove.append(index) }
        }
        return Plan(remove: remove, insert: desired.indices.filter { !kept.contains($0) })
    }
}

/// Temporarily withheld source records are outside reconciliation, not deletions.
public enum HealthExportScope {
    public static func includes<Key: Hashable>(_ key: Key, holding: Set<Key>) -> Bool {
        !holding.contains(key)
    }
}
