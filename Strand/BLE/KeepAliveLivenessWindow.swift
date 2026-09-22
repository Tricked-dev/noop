import Foundation

/// A delayed timer cannot prove that a peripheral ignored keep-alive work: iOS may have suspended
/// the process before that work ran. Require a full silence window of regularly observed callbacks
/// after a gap, allowing the existing battery poll and notifications to demonstrate liveness first.
struct KeepAliveLivenessWindow {
    private var lastTick: TimeInterval?
    private var observationStartedAt: TimeInterval?

    mutating func shouldReconnect(now: TimeInterval, lastDataAt: TimeInterval,
                                  silenceLimit: TimeInterval, expectedTickInterval: TimeInterval) -> Bool {
        if let lastTick, now >= lastTick, now - lastTick <= expectedTickInterval * 2 {
            // Keep observing this uninterrupted run of timer callbacks.
        } else {
            observationStartedAt = now
        }
        lastTick = now
        let observedSince = max(lastDataAt, observationStartedAt ?? now)
        return now - observedSince > silenceLimit
    }

    mutating func reset() {
        lastTick = nil
        observationStartedAt = nil
    }
}
