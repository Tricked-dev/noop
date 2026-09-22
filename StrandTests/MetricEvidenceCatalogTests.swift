import XCTest
import StrandAnalytics
@testable import Strand

final class MetricEvidenceCatalogTests: XCTestCase {
    func testEveryCatalogMetricHasEvidenceIncludingWHOOP34() {
        XCTAssertEqual(MetricCatalog.all.filter { $0.source == "my-whoop" }.count, 34)
        XCTAssertEqual(MetricCatalog.all.filter { $0.source != "xiaomi-band" }.count, 46)
        for metric in MetricCatalog.all {
            XCTAssertNotEqual(MetricEvidence.group(for: metric.key), .unknown, metric.id)
            XCTAssertFalse(MetricEvidenceCopy.explanation(metric.key).isEmpty, metric.id)
        }
    }
}
