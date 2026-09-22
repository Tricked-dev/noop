import XCTest
import WhoopProtocol
@testable import WhoopStore

final class AnalysisContentDigestTests: XCTestCase {
    func testContentCorrectionsAndWindowIsolation() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertDevice(id: "strap", mac: nil, name: nil)
        _ = try await store.insert(Streams(hr: [HRSample(ts: 100, bpm: 70)]), deviceId: "strap")
        let before = try await store.analysisContentDigest(from: 0, to: 200)
        XCTAssertNotNil(before)
        let unchanged = try await store.analysisContentDigest(from: 0, to: 200)
        XCTAssertEqual(before, unchanged)
        try await store.correctDigestTestHR()
        let corrected = try await store.analysisContentDigest(from: 0, to: 200)
        XCTAssertNotEqual(before, corrected, "COUNT and MAX(ts) did not change, but the value did")
        _ = try await store.insert(Streams(hr: [HRSample(ts: 300, bpm: 90)]), deviceId: "strap")
        let outside = try await store.analysisContentDigest(from: 0, to: 200)
        XCTAssertEqual(corrected, outside)
        _ = try await store.insert(Streams(rr: [RRInterval(ts: 100, rrMs: 800)]), deviceId: "strap")
        let rrArrived = try await store.analysisContentDigest(from: 0, to: 200)
        XCTAssertNotEqual(outside, rrArrived)
    }
}

private extension WhoopStore {
    func correctDigestTestHR() throws {
        try syncWrite { db in try db.execute(sql: "UPDATE hrSample SET bpm = 75 WHERE ts = 100") }
    }
}
