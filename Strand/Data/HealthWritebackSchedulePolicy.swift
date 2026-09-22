import Foundation

/// Apple Health export retries are separate from the infrequent repair of destination changes.
/// BackgroundTasks chooses delivery; these are earliest dates, not wake guarantees.
enum HealthWritebackSchedulePolicy {
    static let refreshInterval: TimeInterval = 60 * 60
    static let repairInterval: TimeInterval = 24 * 60 * 60

    static func shouldSchedule(isAuthorized: Bool) -> Bool { isAuthorized }
}

/// Persisted in one value so a killed export cannot leave a success stamp without its pending token.
/// A newer signal arriving during an export must survive that older export's completion.
struct HealthWritebackScheduleState: Codable, Equatable {
    private(set) var pendingToken: String?
    private(set) var retryAt: Date?
    private(set) var repairAt: Date

    init(now: Date) {
        repairAt = now.addingTimeInterval(HealthWritebackSchedulePolicy.repairInterval)
    }

    var nextDate: Date { retryAt ?? repairAt }

    @discardableResult
    mutating func markPending(now: Date, token: String = UUID().uuidString) -> String {
        pendingToken = token
        // New arrivals must not postpone an already-requested retry.
        if retryAt == nil { retryAt = now.addingTimeInterval(HealthWritebackSchedulePolicy.refreshInterval) }
        return token
    }

    mutating func complete(token: String, now: Date) {
        repairAt = now.addingTimeInterval(HealthWritebackSchedulePolicy.repairInterval)
        guard pendingToken == token else { return }
        pendingToken = nil
        retryAt = nil
    }

    /// Failed or deliberately held-back records remain owed, with a bounded retry cadence.
    mutating func retryLater(now: Date) {
        guard pendingToken != nil else { return }
        retryAt = now.addingTimeInterval(HealthWritebackSchedulePolicy.refreshInterval)
    }
}
