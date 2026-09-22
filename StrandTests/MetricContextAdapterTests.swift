import XCTest
import StrandAnalytics
import WhoopStore
@testable import Strand

final class MetricContextAdapterTests: XCTestCase {
    private let day = "2026-09-22"
    private func daily(sleep: Double? = 480, hrv: Double? = 45, skin: Double? = nil,
                       absoluteSkin: Double? = nil, hrOnly: Bool? = nil) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: sleep, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: 60, avgHrv: hrv, recovery: 70,
                    strain: 30, exerciseCount: nil, skinTempDevC: skin, respRateBpm: 15,
                    skinTempC: absoluteSkin, sleepHrOnly: hrOnly)
    }
    private func observations(_ rows: [SourcedDailyMetric], flagged: Bool = false) -> [MetricContext.Observation] {
        MetricContextAdapter.observations(rows: rows, sleeps: [], deviceID: "strap-A",
            whoop4: true, knownDevice: true, hrvWindow: "whole",
            unreliableHRVDays: flagged ? [day] : [], anchorDay: day)
    }

    func testComputedWhoop4ValuesCarryHardwareLimits() {
        let rows = observations([.init(metric: daily(absoluteSkin: 33), source: .noopComputed)])
        for metric in MetricContext.Metric.allCases where metric != .bedtime {
            XCTAssertEqual(rows.first { $0.metric == metric }?.use, MetricContext.whoop4Use(metric))
        }
        XCTAssertTrue(rows.allSatisfy { $0.channel.hasPrefix("strap-A:NOOP computed:") })
    }

    func testHRVOvercountAndHrOnlySleepAreWithheld() {
        let rows = observations([.init(metric: daily(hrOnly: true), source: .noopComputed)], flagged: true)
        XCTAssertEqual(rows.first { $0.metric == .hrv }?.verified, false)
        XCTAssertEqual(rows.first { $0.metric == .sleep }?.verified, false)
    }

    func testImportedValuesDoNotInheritRawSensorLimitAndKeepMethod() {
        let rows = observations([.init(metric: daily(hrv: 80), source: .whoopImport),
                                 .init(metric: daily(hrv: 20), source: .noopComputed)], flagged: true)
        XCTAssertEqual(rows.first { $0.metric == .hrv }?.value, 80)
        XCTAssertEqual(rows.first { $0.metric == .hrv }?.verified, true)
        XCTAssertEqual(rows.first { $0.metric == .respiration }?.use, .estimate)
        let apple = observations([.init(metric: daily(), source: .appleHealth)])
        XCTAssertTrue(apple.first { $0.metric == .hrv }!.channel.hasSuffix(":sdnn"))
        XCTAssertTrue(rows.first { $0.metric == .hrv }!.channel.hasSuffix(":rmssd"))
    }

    func testUnknownSourceAndTemperatureDeviationCannotBecomeAbsoluteReference() {
        let unknown = observations([.init(metric: daily(), source: .localCache)])
        XCTAssertTrue(unknown.allSatisfy { $0.use == .unverified })
        let deviation = observations([.init(metric: daily(skin: 0.5), source: .noopComputed)])
        XCTAssertNil(deviation.first { $0.metric == .skinTemperature })
        let absolute = observations([.init(metric: daily(skin: 0.5, absoluteSkin: 33.2), source: .noopComputed)])
        XCTAssertEqual(absolute.first { $0.metric == .skinTemperature }?.value, 33.2)
    }

    func testPerFieldNamespacesSurviveSelection() {
        let source = DailyMetricSource.noopComputed
        let origins = [MetricContextAdapter.originKey(.hrv, source: source, day: day): "legacy-noop",
                       MetricContextAdapter.originKey(.restingHR, source: source, day: day): "active-noop"]
        let rows = MetricContextAdapter.observations(rows: [.init(metric: daily(), source: source)],
            sleeps: [], deviceID: "active", whoop4: true, knownDevice: true,
            hrvWindow: "whole", unreliableHRVDays: [], anchorDay: day, origins: origins)
        XCTAssertTrue(rows.first { $0.metric == .hrv }!.channel.hasPrefix("legacy-noop:"))
        XCTAssertTrue(rows.first { $0.metric == .restingHR }!.channel.hasPrefix("active-noop:"))
    }
}
