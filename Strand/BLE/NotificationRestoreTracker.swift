/// Coalesces restoration subscription requests until each channel confirms delivery.
/// A second caller must not enqueue another off/on cycle behind a started transfer.
struct NotificationRestoreTracker<Channel: Hashable> {
    private var requested: Set<Channel> = []
    private var pending: Set<Channel> = []

    mutating func request(_ channel: Channel) -> Bool {
        guard requested.insert(channel).inserted else { return false }
        pending.insert(channel)
        return true
    }

    mutating func confirmed(_ channel: Channel) { pending.remove(channel) }

    mutating func failed(_ channel: Channel) {
        // Keep sync gated, but allow the ordinary notification retry to request this channel again.
        requested.remove(channel)
    }

    func hasPending(in channels: [Channel]) -> Bool { channels.contains { pending.contains($0) } }
}
