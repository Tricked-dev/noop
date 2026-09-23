import Foundation
import WhoopProtocol

enum DeviceLogDiagnostics {
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
