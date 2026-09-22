import XCTest
@testable import StrandAnalytics

final class ValidatedCacheTests: XCTestCase {
    func testRoundTripAndInvalidation() throws {
        let now = Date(timeIntervalSince1970: 100000)
        let cache = ValidatedCache(build: "one", configuration: "profile", payload: ["day": [1.25, 2.5]], now: now)
        let data = try PropertyListEncoder().encode(cache)
        let restored = try PropertyListDecoder().decode(ValidatedCache<[String: [Double]]>.self, from: data)
        XCTAssertEqual(restored.value(build: "one", configuration: "profile", now: now), ["day": [1.25, 2.5]])
        XCTAssertNil(restored.value(build: "two", configuration: "profile", now: now))
        XCTAssertNil(restored.value(build: "one", configuration: "edited", now: now))
        XCTAssertNil(restored.value(build: "one", configuration: "profile", now: now.addingTimeInterval(31 * 86400)))
        XCTAssertNil(restored.value(build: "one", configuration: "profile", now: now.addingTimeInterval(-1)))
        XCTAssertThrowsError(try PropertyListDecoder().decode(ValidatedCache<[String: [Double]]>.self, from: Data("corrupt".utf8)))
    }
}
