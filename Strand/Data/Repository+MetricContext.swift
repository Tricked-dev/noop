import Foundation
import StrandAnalytics
import WhoopStore

extension Repository {
    /// An explicit date range and provenance per field, with no cross-source numeric blending.
    /// A failed read invalidates the window rather than silently resembling a low-activity week.
    func contextSeries(key: String, source: String, anchorDay: String) async -> [ActivityGuidance.Point] {
        guard let store = await storeHandle() else { return [] }
        let active = deviceId
        let namespaces = source == "my-whoop" ? importedReadIds + computedReadIds : [source]
        let from = MetricContext.shift(anchorDay, by: -14), to = MetricContext.shift(anchorDay, by: -1)
        guard !from.isEmpty, !to.isEmpty else { return [] }
        var result: [String: ActivityGuidance.Point] = [:]
        for namespace in namespaces {
            guard !Task.isCancelled,
                  let series = try? await store.metricSeries(deviceId: namespace, key: key, from: from, to: to),
                  let daily = try? await store.dailyMetrics(deviceId: namespace, from: from, to: to) else { return [] }
            var values = Dictionary(series.map { ($0.day, $0.value) }, uniquingKeysWith: { first, _ in first })
            for row in daily where values[row.day] == nil { values[row.day] = Self.dailyColumn(key: key, day: row) }
            for (day, value) in values where result[day] == nil {
                result[day] = .init(day: day, value: value, channel: namespace + ":" + key)
            }
        }
        guard deviceId == active, !Task.isCancelled else { return [] }
        return result.values.sorted { $0.day < $1.day }
    }

    /// Only recorded, non-detected strength sessions count, once per local start day.
    /// The count says nothing about whether all major muscle groups were trained.
    func contextStrengthDays(anchorDay: String) async -> [String]? {
        guard let store = await storeHandle() else { return nil }
        let active = deviceId
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current; formatter.dateFormat = "yyyy-MM-dd"
        guard let from = formatter.date(from: MetricContext.shift(anchorDay, by: -7)),
              let to = formatter.date(from: anchorDay) else { return nil }
        var days: [String] = []
        for namespace in Self.workoutNamespaces(rawIds: rawPhysiologyReadIds(store: store)) {
            guard !Task.isCancelled, let rows = try? await store.workouts(deviceId: namespace,
                from: Int(from.timeIntervalSince1970), to: Int(to.timeIntervalSince1970), limit: 5000) else { return nil }
            for row in rows where row.endTs > row.startTs && row.endTs <= Int(to.timeIntervalSince1970) {
                guard WorkoutSource.classify(row.source) != .detected,
                      row.source == "lifting" || ActivityGuidance.isStrengthSport(WorkoutSource.sportKey(row.sport)) else { continue }
                days.append(formatter.string(from: Date(timeIntervalSince1970: Double(row.startTs))))
            }
        }
        guard deviceId == active, !Task.isCancelled else { return nil }
        return days
    }

    /// Keep per-field storage namespaces before the dashboard's coalescing would discard them.
    /// Canonical legacy namespaces do not establish which physical strap originally measured a day.
    func metricContextObservations(anchorDay: String, whoop4: Bool, knownDevice: Bool,
                                   hrvWindow: String) async -> [MetricContext.Observation] {
        guard let store = await storeHandle() else { return [] }
        let active = deviceId
        let sources = importedReadIds.map { ($0, DailyMetricSource.whoopImport) }
            + computedReadIds.map { ($0, DailyMetricSource.noopComputed) }
            + [(Self.appleHealthSource, DailyMetricSource.appleHealth)]
        let start = MetricContext.shift(anchorDay, by: -180)
        var rows: [SourcedDailyMetric] = []
        var origins: [String: String] = [:]
        var unreliable: Set<String> = []
        for (namespace, source) in sources {
            guard !Task.isCancelled else { return [] }
            guard let values = try? await store.dailyMetrics(deviceId: namespace, from: start, to: anchorDay) else { return [] }
            if source == .noopComputed {
                // Historical anchors need flags from the same date window, not 180 days from now.
                guard let flags = try? await store.metricSeries(deviceId: namespace, key: "hrv_rr_overcount", from: start, to: anchorDay) else { return [] }
                unreliable.formUnion(flags.filter { $0.value >= 0.5 }.map(\.day))
            }
            for value in values {
                rows.append(.init(metric: value, source: source))
                for metric in MetricContext.Metric.allCases where MetricContextAdapter.value(metric, in: value) != nil {
                    let key = MetricContextAdapter.originKey(metric, source: source, day: value.day)
                    if origins[key] == nil { origins[key] = namespace }
                }
            }
        }
        guard !Task.isCancelled, deviceId == active else { return [] }
        return MetricContextAdapter.observations(rows: rows, sleeps: sleeps, deviceID: active,
            whoop4: whoop4, knownDevice: knownDevice, hrvWindow: hrvWindow,
            unreliableHRVDays: unreliable, anchorDay: anchorDay, origins: origins)
    }
}
