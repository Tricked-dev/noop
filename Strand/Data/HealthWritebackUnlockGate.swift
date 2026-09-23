import Foundation

/// Retains the widest import window while a Health pass is locked or already running.
struct HealthSyncRequestWindow {
    private(set) var days: Int?

    mutating func request(days: Int) {
        self.days = max(self.days ?? 0, max(1, days))
    }

    mutating func take(covering days: Int) -> Int {
        let result = max(self.days ?? 0, max(1, days))
        self.days = nil
        return result
    }
}

/// Coalesces locked-device write-back requests into one retry when protected data becomes available.
/// The notification is supplied by the iOS bridge; keeping UIKit out allows the lifecycle to be tested
/// without HealthKit, a phone, or an app service starting Bluetooth.
@MainActor
final class HealthWritebackUnlockGate {
    private let center: NotificationCenter
    private let availableNotification: Notification.Name
    private var observer: NSObjectProtocol?
    private var pendingRetry: (() -> Void)?

    init(center: NotificationCenter = .default, availableNotification: Notification.Name) {
        self.center = center
        self.availableNotification = availableNotification
    }

    /// Returns true when the caller should defer. A request already able to run consumes any older debt.
    func deferUntilAvailable(isAvailable: Bool, retry: @escaping () -> Void) -> Bool {
        guard !isAvailable else {
            clear()
            return false
        }
        pendingRetry = retry
        if observer == nil {
            observer = center.addObserver(forName: availableNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let retry = self.pendingRetry
                    self.clear()
                    retry?()
                }
            }
        }
        return true
    }

    private func clear() {
        if let observer { center.removeObserver(observer) }
        observer = nil
        pendingRetry = nil
    }

    deinit {
        if let observer { center.removeObserver(observer) }
    }
}
