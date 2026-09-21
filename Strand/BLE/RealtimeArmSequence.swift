/// Enabling HR can disable the raw stream on WHOOP 4 firmware. Arm raw last so live
/// HR carried by that stream is available immediately, without waiting for the keep-alive.
enum RealtimeArmSequence {
    static func perform(enableHR: () -> Void, enableRaw: () -> Void) {
        enableHR()
        enableRaw()
    }
}
