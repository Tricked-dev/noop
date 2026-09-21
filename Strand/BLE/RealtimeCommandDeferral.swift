/// Coalesces live stream mode changes while history owns the strap transport.
/// Heart-rate notifications remain subscribed; only mode-changing writes wait.
struct RealtimeCommandDeferral {
    enum Stream: CaseIterable, Hashable { case heartRate, raw }
    struct Command: Equatable {
        let stream: Stream
        let enabled: Bool
    }
    private var pending: [Stream: Bool] = [:]

    mutating func remember(_ stream: Stream, enabled: Bool) {
        pending[stream] = enabled
    }

    mutating func takeCommands() -> [Command] {
        // Enabling HR can disable raw on the strap, so raw must be applied last.
        let commands = Stream.allCases.compactMap { stream in
            pending[stream].map { Command(stream: stream, enabled: $0) }
        }
        pending.removeAll(keepingCapacity: true)
        return commands
    }
}
