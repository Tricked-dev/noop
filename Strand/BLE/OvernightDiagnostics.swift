import Foundation

/// A bounded local event journal. Callers serialize writes; no timer or network is created here.
struct BoundedDiagnosticLog {
    let directory: URL
    var maximumBytes = 1_048_576

    func append(event: String, at timestamp: TimeInterval) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        try fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                             ofItemAtPath: directory.path)
        #endif
        var excluded = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
        let current = directory.appendingPathComponent("current.jsonl")
        let previous = directory.appendingPathComponent("previous.jsonl")
        var data = try JSONSerialization.data(withJSONObject: ["at": timestamp,
                                                               "event": String(event.prefix(2_048))],
                                              options: [.sortedKeys])
        data.append(0x0A)
        if let size = try? fm.attributesOfItem(atPath: current.path)[.size] as? NSNumber,
           size.intValue + data.count > maximumBytes {
            if fm.fileExists(atPath: previous.path) { try fm.removeItem(at: previous) }
            try fm.moveItem(at: current, to: previous)
        }
        if !fm.fileExists(atPath: current.path) {
            guard fm.createFile(atPath: current.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            #if os(iOS)
            // Continue recording while the phone is locked after its first unlock.
            try fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                 ofItemAtPath: current.path)
            #endif
        }
        let handle = try FileHandle(forWritingTo: current)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }
}

/// Persist the first capture deadline; relaunches never extend or re-arm an expired capture.
enum DiagnosticCaptureWindow {
    static func deadline(defaults: UserDefaults, key: String, now: TimeInterval,
                         duration: TimeInterval) -> TimeInterval {
        if let existing = defaults.object(forKey: key) as? Double { return existing }
        let deadline = now + duration
        defaults.set(deadline, forKey: key)
        return deadline
    }
}

/// Attribute only the first valid HR notification after a request; both BLE channels share this state.
struct LiveDataStartupTrace {
    private(set) var startedAt: TimeInterval?
    mutating func begin(now: TimeInterval) { if startedAt == nil { startedAt = now } }
    mutating func cancel() { startedAt = nil }
    mutating func finish(now: TimeInterval) -> TimeInterval? {
        guard let start = startedAt else { return nil }
        startedAt = nil
        return max(0, now - start)
    }
}

/// Temporary development capture, automatically inert after its first twenty-four-hour window.
enum OvernightDiagnostics {
    static func shouldRecordBLE(_ message: String) -> Bool {
        if message.hasPrefix("→ Get Battery Level") || message.hasPrefix("→ Historical Data Result") {
            return false
        }
        return ["Backfill: session", "Backfill: idle", "Backfill: no rows", "Backfill: caught up",
                "Backfill: foreground deferred", "Backfill: periodic", "Backfill: waiting",
                "Backfill diagnostic:", "Sync diagnostic: subscriptions=", "Sync diagnostic: inbound=",
                "Connected", "Disconnected", "Connecting", "Reconnecting", "Connect settled:",
                "Central state:", "BONDED", "Notify ", "Clock", "No data for", "Signal:", "Link epitaph:", "send(", "→ "]
            .contains { message.hasPrefix($0) }
    }

    #if NOOP_SYNC_DIAGNOSTICS && os(iOS)
    private static let queue = DispatchQueue(label: "noop.overnight-diagnostics", qos: .utility)
    static let captureUntil = DiagnosticCaptureWindow.deadline(
        defaults: .standard, key: "diagnostics.daytime.427.endsAt",
        now: Date().timeIntervalSince1970, duration: 24 * 3_600)
    static var isActive: Bool { Date().timeIntervalSince1970 <= captureUntil }
    private static let writer = BoundedDiagnosticLog(directory:
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DaytimeDiagnostics", isDirectory: true))

    static func record(_ event: @autoclosure () -> String) {
        let now = Date().timeIntervalSince1970
        guard now <= captureUntil else { return }
        let message = event()
        queue.async {
            do { try writer.append(event: message, at: now) }
            catch { NSLog("Overnight diagnostic write failed: %@", error.localizedDescription) }
        }
    }

    static func start() {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        record("capture-start build=\(build) expires=\(captureUntil) window=24h maxFiles=2 maxFileBytes=1048576")
    }
    #endif
}
