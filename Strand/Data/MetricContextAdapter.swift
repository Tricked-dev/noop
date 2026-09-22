import Foundation
import StrandAnalytics
import WhoopStore

/// Selects source-tagged observations without changing the repository's stored or scored values.
enum MetricContextAdapter {
    static func observations(rows: [SourcedDailyMetric], sleeps: [CachedSleepSession],
                             deviceID: String, whoop4: Bool, knownDevice: Bool,
                             hrvWindow: String, unreliableHRVDays: Set<String>,
                             anchorDay: String, origins: [String: String] = [:]) -> [MetricContext.Observation] {
        let cutoff = MetricContext.shift(anchorDay, by: -180)
        let eligible = rows.filter { $0.metric.day >= cutoff && $0.metric.day <= anchorDay }
        let sparseDays = Set(sleeps.filter { $0.stagingSparse == true }.map {
            Repository.localDayKey(Date(timeIntervalSince1970: Double($0.endTs)))
        })
        var result: [MetricContext.Observation] = []
        for metric in MetricContext.Metric.allCases where metric != .bedtime {
            let key: String
            switch metric {
            case .restingHR: key = "rhr"
            case .hrv: key = "hrv"
            case .respiration: key = "resp"
            case .skinTemperature: key = "skin"
            default: key = metric.rawValue
            }
            var chosen: [String: SourcedDailyMetric] = [:]
            let sources = DailyMetricSource.vitalPrecedence(for: key)
            for source in sources {
                for row in eligible where row.source == source && chosen[row.metric.day] == nil {
                    if value(metric, in: row.metric) != nil { chosen[row.metric.day] = row }
                }
            }
            for (day, row) in chosen {
                guard let value = value(metric, in: row.metric) else { continue }
                let source = sourceID(row.source)
                let computed = row.source == .noopComputed
                var verified = true
                var use: MetricContext.MeasurementUse = .estimate
                var semantics = metric.rawValue
                if metric == .hrv {
                    semantics = row.source == .appleHealth ? "sdnn" : "rmssd"
                    if computed { semantics += ":" + hrvWindow }
                    verified = row.source != .localCache && !(computed && unreliableHRVDays.contains(day))
                    use = .trendOnly
                }
                if [.effort, .skinTemperature].contains(metric) { use = .trendOnly }
                if metric == .sleep, computed {
                    verified = row.metric.sleepHrOnly != true && !sparseDays.contains(day)
                    use = .trendOnly
                }
                if computed && whoop4 { use = MetricContext.whoop4Use(metric) }
                if computed && !knownDevice && [.respiration, .skinTemperature].contains(metric) { use = .unverified }
                if row.source == .localCache { use = .unverified }
                let origin = origins[originKey(metric, source: row.source, day: day)] ?? deviceID
                result.append(.init(metric, day: day, value: value,
                                    channel: origin + ":" + source + ":" + semantics,
                                    verified: verified, use: use))
            }
        }
        // Session timing is descriptive, not a new SRI or sleep-stage estimate. Unknown provenance
        // and sparse staging are withheld. Use the longest completed session for each wake date.
        let sessions = sleeps.filter { $0.endTs > $0.effectiveStartTs && $0.stagingSparse != true && $0.deviceId != nil }
        let grouped = Dictionary(grouping: sessions) {
            Repository.localDayKey(Date(timeIntervalSince1970: Double($0.endTs)))
        }
        for (day, entries) in grouped where day >= cutoff && day <= anchorDay {
            guard let session = entries.max(by: { $0.endTs - $0.effectiveStartTs < $1.endTs - $1.effectiveStartTs }) else { continue }
            let start = Date(timeIntervalSince1970: Double(session.effectiveStartTs))
            let parts = Calendar.current.dateComponents([.hour, .minute], from: start)
            let minutes = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            result.append(.init(.bedtime, day: day, value: minutes,
                                channel: (session.deviceId ?? deviceID) + ":sleep-timing", use: .trendOnly))
        }
        return result.sorted { ($0.metric.rawValue, $0.day, $0.channel) < ($1.metric.rawValue, $1.day, $1.channel) }
    }

    static func sourceID(_ source: DailyMetricSource) -> String {
        switch source {
        case .whoopImport: return "WHOOP import"
        case .noopComputed: return "NOOP computed"
        case .appleHealth: return "Apple Health"
        case .localCache: return "Unspecified source"
        }
    }

    static func originKey(_ metric: MetricContext.Metric, source: DailyMetricSource, day: String) -> String {
        metric.rawValue + ":" + sourceID(source) + ":" + day
    }

    static func value(_ metric: MetricContext.Metric, in day: DailyMetric) -> Double? {
        switch metric {
        case .restingHR: return day.restingHr.map(Double.init)
        case .hrv: return day.avgHrv
        case .respiration: return day.respRateBpm
        case .skinTemperature:
            return day.skinTempC ?? day.skinTempDevC.flatMap { VitalBands.isAbsoluteSkinTemp($0) ? $0 : nil }
        case .sleep: return day.totalSleepMin
        case .effort: return day.strain
        case .bedtime: return nil
        }
    }
}
