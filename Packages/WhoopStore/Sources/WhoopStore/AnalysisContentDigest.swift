import Foundation
import GRDB
#if canImport(CryptoKit)
import CryptoKit
#endif

extension WhoopStore {
    /// Strong witness for cold-process analysis reuse. Unlike COUNT/MAX it catches in-place
    /// corrections. Streams all owners to include alias sources. No raw rows escape the read
    /// transaction. This is a read-only Apple cache optimization; no schema or data changes.
    public func analysisContentDigest(from: Int, to: Int) async throws -> String? {
        #if canImport(CryptoKit)
        return try syncRead { db in
            var hash = SHA256()
            var buffer = Data()
            func add(_ data: Data) {
                var length = UInt64(data.count).bigEndian
                withUnsafeBytes(of: &length) { buffer.append(contentsOf: $0) }
                buffer.append(data)
                if buffer.count >= 65536 { hash.update(data: buffer); buffer.removeAll(keepingCapacity: true) }
            }
            func addValue(_ value: DatabaseValue) {
                switch value.storage {
                case .null: add(Data([0]))
                case .int64(let number):
                    add(Data([1])); var bits = number.bigEndian
                    withUnsafeBytes(of: &bits) { add(Data($0)) }
                case .double(let number):
                    add(Data([2])); var bits = number.bitPattern.bigEndian
                    withUnsafeBytes(of: &bits) { add(Data($0)) }
                case .string(let string): add(Data([3])); add(Data(string.utf8))
                case .blob(let data): add(Data([4])); add(data)
                }
            }
            let tables = ["hrSample", "ppgHrSample", "rrInterval", "respSample", "gravitySample",
                          "stepSample", "skinTempSample", "spo2Sample", "event", "sleepStateSample", "v18AuxSample"]
            for table in tables {
                try Task.checkCancellation()
                add(Data(table.utf8))
                let rows = try Row.fetchCursor(db, sql: "SELECT * FROM \(table) WHERE ts >= ? AND ts <= ? ORDER BY rowid",
                                               arguments: [from, to])
                while let row = try rows.next() {
                    try Task.checkCancellation()
                    for (name, value) in row {
                        add(Data(name.utf8))
                        addValue(value)
                    }
                }
            }
            // Registry policy and previously banked band sleep-state can also affect interpretation.
            for sql in ["SELECT * FROM pairedDevice ORDER BY rowid",
                        "SELECT * FROM sleepSession WHERE endTs >= \(from) AND startTs <= \(to) ORDER BY rowid"] {
                let rows = try Row.fetchCursor(db, sql: sql)
                while let row = try rows.next() {
                    for (name, value) in row { add(Data(name.utf8)); addValue(value) }
                }
            }
            hash.update(data: buffer)
            return hash.finalize().map { String(format: "%02x", $0) }.joined()
        }
        #else
        return nil // No persisted reuse on platforms without the digest implementation.
        #endif
    }
}
