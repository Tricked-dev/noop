import Foundation
import WhoopProtocol

enum DeviceLogDiagnostics {
    /// A data frontier is not a wake time. Emit both so a partial sync is identifiable.
    static func sleepBoundaryLine(day: String, readEnd: Int, hrCount: Int, hrLast: Int?,
                                  motionCount: Int, motionLast: Int?,
                                  sessions: [(start: Int, end: Int)]) -> String {
        let bounds = sessions.prefix(8).map { "\($0.start):\($0.end)" }.joined(separator: ",")
        return "sleep-boundary day=\(day) readEnd=\(readEnd) hr=\(hrCount) hrLast=\(hrLast.map(String.init) ?? "none") "
            + "motion=\(motionCount) motionLast=\(motionLast.map(String.init) ?? "none") "
            + "sessions=\(sessions.count) bounds=[\(bounds)] truncated=\(sessions.count > 8)"
    }

    // Each notification remains one fragment. Never invent text across missing notifications.
    // DIAGNOSTIC BATTERY COST: bounded escaping per existing console append; no extra writes.
    static func consoleFragment(_ text: String) -> String {
        let scalars = text.unicodeScalars
        let escaped = scalars.prefix(300).map { scalar -> String in
            switch scalar.value {
            case 92: return "\\\\"
            case 10: return "\\n"
            case 13: return "\\r"
            case 9: return "\\t"
            case 0..<32, 127...159, 0x2028, 0x2029:
                return String(format: "\\u{%04X}", scalar.value)
            default: return String(scalar)
            }
        }.joined()
        return escaped + (scalars.count > 300 ? " [fragment truncated]" : "")
    }

    // Explains already-rejected frames only; this must never decide what gets stored or ACKed.
    static func rejectionReason(_ frame: ParsedFrame, unmapped: Bool) -> String {
        if !frame.ok { return "integrity-\(frame.rejectReason.rawValue)" }
        if frame.crcOK == false { return "payload-crc" }
        if unmapped { return "unmapped-layout" }
        if frame.parsed["unix"]?.intValue == nil { return "missing-timestamp" }
        if frame.parsed["heart_rate"]?.intValue == nil && frame.parsed["gravity_x"]?.doubleValue == nil {
            return "no-usable-hr-or-motion"
        }
        return "other-rejection"
    }
}

/// Coalesces repeated deferrals per trigger/reason without changing sync eligibility.
/// Callers supply only the fixed sync-policy reasons; no sensor or packet data is retained.
struct SyncDeferralLogGate {
    private struct Entry {
        var emittedAt: TimeInterval
        var suppressed: Int
    }
    private var entries: [String: Entry] = [:]

    /// Nil suppresses a repeat; a value emits the number skipped since the previous line.
    mutating func suppressedCountToEmit(trigger: BackfillTrigger, reason: String,
                                       now: TimeInterval) -> Int? {
        let key = "\(trigger):\(reason)"
        if var entry = entries[key], now >= entry.emittedAt, now - entry.emittedAt < 60 {
            entry.suppressed += 1
            entries[key] = entry
            return nil
        }
        let suppressed = entries[key]?.suppressed ?? 0
        entries[key] = Entry(emittedAt: now, suppressed: 0)
        return suppressed
    }
}
