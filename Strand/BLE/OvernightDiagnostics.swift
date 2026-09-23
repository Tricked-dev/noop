import Foundation
#if os(iOS)
import UIKit
#endif

/// Monotonic stage durations include scheduling and suspension, not just CPU execution.
struct DiagnosticStageTrace {
    let startedAt: TimeInterval
    private var previousAt: TimeInterval
    private(set) var stages: [String] = []

    init(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        startedAt = now
        previousAt = now
    }

    mutating func mark(_ name: String, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        stages.append("\(name)=\(Int(max(0, now - previousAt) * 1_000))ms")
        previousAt = now
    }

    func elapsed(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> TimeInterval {
        max(0, now - startedAt)
    }
}

/// Keep burst diagnostics bounded while accounting for the events suppressed between emissions.
struct DiagnosticEmissionGate {
    private var lastEmission: TimeInterval?
    private var suppressed = 0

    mutating func take(now: TimeInterval, interval: TimeInterval) -> Int? {
        if let lastEmission, now - lastEmission < interval {
            suppressed += 1
            return nil
        }
        lastEmission = now
        defer { suppressed = 0 }
        return suppressed
    }
}

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
                "Connected", "Disconnected", "Failed to connect", "Connecting", "Reconnecting", "Connect settled:",
                "Central state:", "BONDED", "Notify ", "Clock", "No data for", "Signal:", "Link epitaph:", "send(", "→ "]
            .contains { message.hasPrefix($0) }
    }

    #if NOOP_SYNC_DIAGNOSTICS && os(iOS)
    private static let queue = DispatchQueue(label: "noop.overnight-diagnostics", qos: .utility)
    static let captureUntil = DiagnosticCaptureWindow.deadline(
        defaults: .standard, key: "diagnostics.performance.v1.endsAt",
        now: Date().timeIntervalSince1970, duration: 24 * 3_600)
    static var isActive: Bool { Date().timeIntervalSince1970 <= captureUntil }
    private static let writer = BoundedDiagnosticLog(directory:
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DebugDiagnostics", isDirectory: true))

    // DIAGNOSTIC BATTERY COST: hot-path counters add work to view evaluation/log publication.
    // They are plain memory, never Observable/Published, and do not trigger another render or write.
    @MainActor private static var counters: [String: Int] = [:]
    @MainActor private static var spanGates: [String: DiagnosticEmissionGate] = [:]
    @MainActor private static var lastSnapshot: (uptime: TimeInterval, cpu: Double?)?

    @MainActor static func count(_ area: String) {
        guard isActive else { return }
        let state = UIApplication.shared.applicationState == .active ? "active" : "nonactive"
        counters[area + "." + state, default: 0] += 1
    }

    /// Called only by existing lifecycle/sync/keep-alive events; never creates a diagnostic timer.
    @MainActor static func performanceSnapshot(reason: String) {
        guard isActive else { return }
        // DIAGNOSTIC BATTERY COST: one process CPU read, formatting, and journal append per snapshot.
        let now = ProcessInfo.processInfo.systemUptime
        let cpu = RescoreBackgroundScheduler.processCPUSeconds()
        let delta = lastSnapshot.map { previous in
            let cpuDelta: String
            if let cpu, let before = previous.cpu {
                cpuDelta = String(Int(max(0, cpu - before) * 1_000))
            } else { cpuDelta = "unavailable" }
            return "elapsedMs=\(Int(max(0, now - previous.uptime) * 1_000)) processCpuMs=\(cpuDelta)"
        } ?? "baseline=true"
        let counts = counters.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        counters.removeAll(keepingCapacity: true)
        lastSnapshot = (now, cpu)
        record("performance reason=\(reason) app=\(UIApplication.shared.applicationState.rawValue) \(delta) \(counts)")
    }

    @MainActor static func finishSpan(_ area: String, trace: DiagnosticStageTrace, outcome: String) {
        guard isActive else { return }
        // DIAGNOSTIC BATTERY COST: stage clocks per chunk/pass; at most one normal line / 30 s
        // and one slow/failed line / 5 s per area. These writes bypass the published strap log.
        let elapsed = trace.elapsed()
        let slow = elapsed >= 1 || outcome.contains("not-acked")
        let key = area + (slow ? ".slow" : ".normal")
        var gate = spanGates[key] ?? DiagnosticEmissionGate()
        let suppressed = gate.take(now: ProcessInfo.processInfo.systemUptime, interval: slow ? 5 : 30)
        spanGates[key] = gate
        guard let suppressed else { return }
        record("stages area=\(area) outcome=\(outcome) elapsedMs=\(Int(elapsed * 1_000)) suppressed=\(suppressed) \(trace.stages.joined(separator: " "))")
    }

    static func record(_ event: @autoclosure () -> String) {
        let now = Date().timeIntervalSince1970
        guard now <= captureUntil else { return }
        let message = event()
        // DIAGNOSTIC BATTERY COST: JSON encoding and file operations on the utility queue.
        queue.async {
            do { try writer.append(event: message, at: now) }
            catch { NSLog("Overnight diagnostic write failed: %@", error.localizedDescription) }
        }
    }

    @MainActor static func start() {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        record("capture-start build=\(build) expires=\(captureUntil) window=24h maxFiles=2 maxFileBytes=1048576")
        record("diagnostic-battery-cost areas=view-counters,animation-counters,log-counters,stage-clocks,journal-writes,signal-reads; no-new-timers; measurements-include-instrumentation")
        performanceSnapshot(reason: "launch")
    }
    #endif
}
