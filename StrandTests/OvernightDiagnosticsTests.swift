import XCTest
@testable import Strand

final class OvernightDiagnosticsTests: XCTestCase {
    func testJournalPersistsAcrossWriterInstancesAndEscapesNewlines() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try BoundedDiagnosticLog(directory: directory).append(event: "connected\nwith HR", at: 123)
        try BoundedDiagnosticLog(directory: directory).append(event: "completed", at: 456)
        let lines = try String(contentsOf: directory.appendingPathComponent("current.jsonl")).split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        let first = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any])
        XCTAssertEqual(first["event"] as? String, "connected\nwith HR")
        XCTAssertEqual(first["at"] as? Double, 123)
    }

    func testRotationKeepsTwoBoundedFilesAndNewestEvents() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = BoundedDiagnosticLog(directory: directory, maximumBytes: 128)
        for i in 0..<50 { try writer.append(event: "event-\(i)", at: Double(i)) }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(Set(files.map(\.lastPathComponent)), ["current.jsonl", "previous.jsonl"])
        for file in files { XCTAssertLessThanOrEqual(try Data(contentsOf: file).count, 128) }
        XCTAssertTrue(try String(contentsOf: directory.appendingPathComponent("current.jsonl")).contains("event-49"))
    }

    func testCaptureSelectsLifecycleAndOutcomeEventsWithoutPacketFlood() {
        for message in ["Backfill: session started", "Backfill diagnostic: elapsed=5000ms",
                        "Disconnected — timeout", "→ Toggle Realtime HR payload=01", "Notify active data"] {
            XCTAssertTrue(OvernightDiagnostics.shouldRecordBLE(message))
        }
        for message in ["strap: sensor console", "Backfill: ACK prepared for 50 frames",
                        "→ Historical Data Result payload=01", "→ Get Battery Level payload=00",
                        "Sync diagnostic RX bytes=244", "HR notify: 64 bpm"] {
            XCTAssertFalse(OvernightDiagnostics.shouldRecordBLE(message))
        }
    }
    func testDaytimeDeadlineSurvivesRelaunchAndDoesNotRearmAfterExpiry() {
        let name = "DaytimeDiagnosticsTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let key = "capture.endsAt"
        let first = DiagnosticCaptureWindow.deadline(defaults: defaults, key: key, now: 100, duration: 86_400)
        XCTAssertEqual(first, 86_500)
        XCTAssertEqual(DiagnosticCaptureWindow.deadline(defaults: defaults, key: key,
                                                       now: 200, duration: 86_400), first)
        XCTAssertEqual(DiagnosticCaptureWindow.deadline(defaults: defaults, key: key,
                                                       now: 100_000, duration: 86_400), first)
    }

    func testFirstLiveSampleIsRecordedOnceAcrossNotificationChannels() {
        var trace = LiveDataStartupTrace()
        XCTAssertNil(trace.finish(now: 10))
        trace.begin(now: 20)
        trace.begin(now: 30)
        XCTAssertEqual(trace.finish(now: 65), 45)
        XCTAssertNil(trace.finish(now: 66))
        trace.begin(now: 70)
        trace.cancel()
        XCTAssertNil(trace.finish(now: 80))
        trace.begin(now: 90)
        XCTAssertEqual(trace.finish(now: 92), 2)
    }
}
