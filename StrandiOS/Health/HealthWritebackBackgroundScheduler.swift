#if os(iOS)
import BackgroundTasks
import Foundation

/// Retry pending Apple Health exports after an hour; repair external deletions or missed signals
/// daily after a successful reconciliation. Fresh offloads still use the immediate completion hook.
@MainActor
enum HealthWritebackBackgroundScheduler {
    static let taskIdentifier = (Bundle.main.bundleIdentifier ?? "com.noopapp.noop") + ".healthwriteback"

    /// Register at launch, before the first scene finishes connecting. The operation returns whether
    /// the HealthKit write completed; authorization absence is a successful no-op and cancels the next
    /// request in the app-owned closure.
    static func register(perform operation: @escaping @MainActor () async -> Bool) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            let completion = TaskCompletionGuard(task: task)
            let worker = Task { @MainActor in
                // Record debt before the first await. Expiration or process death leaves the retry
                // armed, and only the bridge's completed reconciliation can settle it.
                markPending(retrying: true)
                let succeeded = await operation()
                guard !Task.isCancelled else { return }
                completion.finish(success: succeeded)
            }
            task.expirationHandler = {
                worker.cancel()
                completion.finish(success: false)
            }
        }
    }

    private static let stateKey = "noop.healthWritebackSchedule.v1"

    private static func loadState(now: Date) -> HealthWritebackScheduleState {
        if let data = UserDefaults.standard.data(forKey: stateKey),
           let state = try? PropertyListDecoder().decode(HealthWritebackScheduleState.self, from: data) {
            return state
        }
        let state = HealthWritebackScheduleState(now: now)
        saveState(state)
        return state
    }

    private static func saveState(_ state: HealthWritebackScheduleState) {
        if let data = try? PropertyListEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: stateKey)
        }
    }

    @discardableResult
    static func markPending(now: Date = Date(), retrying: Bool = false) -> String {
        var state = loadState(now: now)
        let token = state.markPending(now: now)
        // A delivered request may already be overdue. Move its successor before awaiting work so
        // expiration cannot leave another immediately-due retry spinning in the background.
        if retrying { state.retryLater(now: now) }
        saveState(state)
        schedule(now: now)
        return token
    }

    static func complete(token: String, now: Date = Date()) {
        var state = loadState(now: now)
        state.complete(token: token, now: now)
        saveState(state)
        schedule(now: now)
    }

    static func retryLater(now: Date = Date()) {
        var state = loadState(now: now)
        state.retryLater(now: now)
        saveState(state)
        schedule(now: now)
    }

    /// Lifecycle transitions repair a lost request using the same persisted date, so reopening the
    /// app cannot continuously push an outstanding retry into the future.
    static func schedule(now: Date = Date()) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = loadState(now: now).nextDate
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }

    static func updateSchedule(isAuthorized: Bool) {
        if HealthWritebackSchedulePolicy.shouldSchedule(isAuthorized: isAuthorized) {
            schedule()
        } else {
            cancel()
        }
    }

    /// `BGTask` completion is single-shot even when normal completion races expiration.
    private final class TaskCompletionGuard: @unchecked Sendable {
        private let task: BGTask
        private let lock = NSLock()
        private var finished = false

        init(task: BGTask) { self.task = task }

        func finish(success: Bool) {
            lock.lock()
            defer { lock.unlock() }
            guard !finished else { return }
            finished = true
            task.setTaskCompleted(success: success)
            task.expirationHandler = nil
        }
    }
}
#endif
