import Foundation

/// Presentation cadence only; Bluetooth and sensor acquisition retain the release behavior.
public enum BackgroundWorkPolicy {
    public static func activityDue(elapsed: TimeInterval, changed: Bool, background: Bool) -> Bool {
        if elapsed < 0 { return true }
        return elapsed >= 60 || (changed && elapsed >= (background ? 15 : 2))
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
