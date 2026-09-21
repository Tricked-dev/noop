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

/// Temporary development capture, automatically inert after its first twelve-hour window.
enum OvernightDiagnostics {
    static func shouldRecordBLE(_ message: String) -> Bool {
        if message.hasPrefix("→ Get Battery Level") || message.hasPrefix("→ Historical Data Result") {
            return false
        }
        return ["Backfill: session", "Backfill: idle", "Backfill: no rows", "Backfill: caught up",
                "Backfill: foreground deferred", "Backfill: periodic", "Backfill: waiting",
                "Backfill diagnostic:", "Sync diagnostic: subscriptions=", "Sync diagnostic: inbound=",
                "Connected", "Disconnected", "Connecting", "Reconnecting", "Connect settled:",
                "Central state:", "BONDED", "Notify ", "Clock", "No data for", "send(", "→ "]
            .contains { message.hasPrefix($0) }
    }

    #if NOOP_SYNC_DIAGNOSTICS && os(iOS)
    private static let queue = DispatchQueue(label: "noop.overnight-diagnostics", qos: .utility)
    private static let captureUntil: TimeInterval = {
        let defaults = UserDefaults.standard
        let key = "diagnostics.overnight.424.endsAt"
        if let existing = defaults.object(forKey: key) as? Double { return existing }
        let deadline = Date().timeIntervalSince1970 + 12 * 3_600
        defaults.set(deadline, forKey: key)
        return deadline
    }()
    private static let writer = BoundedDiagnosticLog(directory:
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OvernightDiagnostics", isDirectory: true))

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
        record("capture-start build=424 expires=\(captureUntil) window=12h maxFiles=2 maxFileBytes=1048576")
    }
    #endif
}
