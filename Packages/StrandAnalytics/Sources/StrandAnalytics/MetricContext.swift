import Foundation

/// Informational context for the iOS metric surfaces. Never feeds recovery or stored measurements.
public enum MetricContext {
    public enum MeasurementUse: String, Codable, Sendable {
        case estimate, trendOnly, unverified
    }

    /// Conservative classification of NOOP-computed WHOOP 4 measurements, not imported app data.
    /// Sensor conversion and sparse staging limits are documented in PROTOCOL_SENSORS.md and #345.
    public static func whoop4Use(_ metric: Metric) -> MeasurementUse {
        switch metric {
        case .restingHR: return .estimate
        case .respiration: return .unverified
        default: return .trendOnly
        }
    }
    public enum Metric: String, CaseIterable, Codable, Sendable {
        case restingHR, hrv, respiration, skinTemperature, sleep, effort, bedtime

        public var configuration: MetricCfg? {
            switch self {
            case .restingHR: return Baselines.restingHRCfg
            case .hrv: return Baselines.hrvCfg
            case .respiration: return Baselines.respCfg
            case .skinTemperature: return Baselines.metricCfg["skin_temp"]
            default: return nil
            }
        }
    }

    public struct Observation: Hashable, Sendable {
        public let metric: Metric
        public let day: String
        public let value: Double
        // Includes source, device, and measurement semantics. Unknown HRV methods are ineligible.
        public let channel: String
        public let verified: Bool
        public let use: MeasurementUse
        public init(_ metric: Metric, day: String, value: Double, channel: String, verified: Bool = true,
                    use: MeasurementUse = .estimate) {
            self.metric = metric; self.day = day; self.value = value
            self.channel = channel; self.verified = verified; self.use = use
        }
    }

    public struct Profile: Hashable, Sendable {
        public let confirmedAge: Int?
        public let sex: String?
        public let heightCM: Double?
        public init(confirmedAge: Int?, sex: String? = nil, heightCM: Double? = nil) {
            self.confirmedAge = confirmedAge; self.sex = sex; self.heightCM = heightCM
        }
    }

    public enum State: String, Sendable {
        case below, within, above, learning, stale, unverified, missing, descriptive
    }
    public enum Basis: String, Sendable { case personal, recommendation, none }

    public struct Reading: Equatable, Sendable, Identifiable {
        public var id: String { metric.rawValue }
        public let metric: Metric
        public let observation: Observation?
        public let state: State
        public let basis: Basis
        public let lower: Double?
        public let upper: Double?
        public let center: Double?
        public let nights: Int
        public let referenceStart: String?
        public let referenceEnd: String?
        public let referenceID: String?
    }

    public struct Week: Equatable, Sendable {
        public let start: String
        public let end: String
        public let count: Int
        public let value: Double?
    }
    public struct Comparison: Equatable, Sendable, Identifiable {
        public var id: String { metric.rawValue }
        public let metric: Metric
        public let previous: Week
        public let recent: Week
        public let compatible: Bool
        public var delta: Double? {
            guard compatible, let a = previous.value, let b = recent.value else { return nil }
            return b - a
        }
    }

    public enum InsightKind: String, Sendable { case sleepOpportunity, sustainedChange, weeklyChange }
    public struct Insight: Equatable, Sendable, Identifiable {
        public var id: String { kind.rawValue + ":" + metric.rawValue }
        public let kind: InsightKind
        public let metric: Metric
        public let direction: State
        public let observationCount: Int
    }
    public struct Snapshot: Equatable, Sendable {
        public let anchorDay: String
        public let readings: [Reading]
        public let comparisons: [Comparison]
        public let insights: [Insight]
    }

    /// CDC age table; the adult minimum is the AASM/SRS consensus, not an estimated personal need.
    /// Neither sex nor height changes these recommendations. No age-adjusted HRV table is inferred.
    public static func sleepTarget(profile: Profile) -> (lower: Double, upper: Double?)? {
        guard let age = profile.confirmedAge else { return nil }
        switch age {
        case 13...17: return (480, 600)
        case 18...60: return (420, nil)
        case 61...64: return (420, 540)
        case 65...120: return (420, 480)
        default: return nil
        }
    }

    // Source identity and quality are part of the reference. A duplicate day is withheld, never
    // counted twice or selected based on input ordering. Padding runs to yesterday, not the last row.
    public static func reading(metric: Metric, observations: [Observation], anchorDay: String,
                               profile: Profile, resetDay: String? = nil) -> Reading {
        let series = unique(observations.filter { $0.metric == metric && $0.day <= anchorDay })
        let current = series.last
        func result(_ state: State, basis: Basis = .none, lower: Double? = nil, upper: Double? = nil,
                    center: Double? = nil, nights: Int = 0, start: String? = nil,
                    end: String? = nil, reference: String? = nil) -> Reading {
            Reading(metric: metric, observation: current, state: state, basis: basis,
                    lower: lower, upper: upper, center: center, nights: nights,
                    referenceStart: start, referenceEnd: end, referenceID: reference)
        }
        guard validDay(anchorDay), let current else { return result(.missing) }
        guard current.verified, current.use != .unverified, isPlausible(current) else { return result(.unverified) }
        guard current.day >= shift(anchorDay, by: -Baselines.vitalCarryDays) else { return result(.stale) }
        if metric == .sleep {
            guard let target = sleepTarget(profile: profile) else { return result(.descriptive) }
            let state: State = current.use == .trendOnly ? .descriptive : current.value < target.lower ? .below
                : (target.upper.map { current.value > $0 } == true ? .above : .within)
            return result(state, basis: .recommendation, lower: target.lower, upper: target.upper,
                          reference: "sleep-age")
        }
        guard let cfg = metric.configuration else { return result(.descriptive) }
        guard !current.channel.isEmpty else { return result(.unverified) }
        let end = shift(current.day, by: -1)
        var start = max(shift(current.day, by: -180), resetDay ?? "0000-00-00")
        // A switch in measurement source or semantics starts a new reference, rather than mixing
        // incompatible HRV methods or quietly comparing a new device against an old one.
        if let switchDay = series.last(where: { $0.day < current.day && $0.channel != current.channel })?.day {
            start = max(start, shift(switchDay, by: 1))
        }
        let prior = series.filter { $0.day >= start && $0.day <= end && $0.channel == current.channel }
        let byDay = Dictionary(uniqueKeysWithValues: prior.map { ($0.day, $0) })
        let dates = days(from: max(start, prior.first?.day ?? current.day), through: end)
        let values = dates.map { day -> Double? in
            guard let row = byDay[day], row.verified, row.use != .unverified, isPlausible(row) else { return nil }
            return row.value
        }
        let baseline = Baselines.foldHistory(values, cfg: cfg)
        guard baseline.trusted else {
            return result(baseline.status == .stale ? .stale : .learning, nights: baseline.nValid,
                          start: dates.first, end: dates.last)
        }
        let width = VitalBands.sigmaK * 1.253 * baseline.spread
        let lower = max(cfg.minVal, baseline.baseline - width)
        let upper = min(cfg.maxVal, baseline.baseline + width)
        // Use the same deviation calculation as VitalBands, including its boundary rounding.
        let z = Baselines.deviation(current.value, state: baseline).z
        let state: State = abs(z) <= VitalBands.sigmaK ? .within : (z < 0 ? .below : .above)
        return result(state, basis: .personal, lower: lower, upper: upper, center: baseline.baseline,
                      nights: baseline.nValid, start: dates.first, end: dates.last,
                      reference: metric == .hrv ? "hrv-method" : "personal-baseline")
    }

    public static func compare(metric: Metric, observations: [Observation], anchorDay: String) -> Comparison {
        let series = unique(observations.filter { $0.metric == metric && $0.day < anchorDay })
        let recentStart = shift(anchorDay, by: -7), previousStart = shift(anchorDay, by: -14)
        let prior = series.filter { $0.day >= previousStart && $0.day < recentStart }
        let recent = series.filter { $0.day >= recentStart && $0.day < anchorDay }
        let rows = prior + recent
        let compatible = validDay(anchorDay) && !rows.isEmpty && rows.allSatisfy { $0.verified && $0.use != .unverified && isPlausible($0) && !$0.channel.isEmpty }
            && Set(rows.map(\.channel)).count == 1
        func week(_ entries: [Observation], start: String) -> Week {
            let values = entries.filter { $0.verified && $0.use != .unverified && isPlausible($0) }.map(\.value)
            let minimum = metric == .effort ? 7 : 5
            var value: Double?
            if compatible && values.count >= minimum {
                if metric == .bedtime {
                    // Circular standard deviation, in minutes. Unstable opposite phases are withheld.
                    let angles = values.map { $0 * 2 * Double.pi / 1440 }
                    let x = angles.map(cos).reduce(0, +) / Double(angles.count)
                    let y = angles.map(sin).reduce(0, +) / Double(angles.count)
                    let r = min(1, hypot(x, y))
                    value = r > 0.1 ? sqrt(-2 * log(r)) * 1440 / (2 * .pi) : nil
                } else {
                    let sum = values.reduce(0, +)
                    value = metric == .effort ? sum : sum / Double(values.count)
                }
            }
            return Week(start: start, end: shift(start, by: 6), count: values.count, value: value)
        }
        return Comparison(metric: metric, previous: week(prior, start: previousStart),
                          recent: week(recent, start: recentStart), compatible: compatible)
    }

    public static func evaluate(observations: [Observation], anchorDay: String, profile: Profile,
                                hrvResetDay: String? = nil, recoveryResetDay: String? = nil) -> Snapshot {
        let readings = Metric.allCases.filter { $0 != .bedtime }.map { metric in
            reading(metric: metric, observations: observations, anchorDay: anchorDay, profile: profile,
                    resetDay: metric == .hrv ? hrvResetDay : recoveryResetDay)
        }
        let comparisons = Metric.allCases.map { metric in
            let reset = metric == .hrv ? hrvResetDay : recoveryResetDay
            return compare(metric: metric, observations: observations.filter { $0.day >= (reset ?? "") }, anchorDay: anchorDay)
        }
        var insights: [Insight] = []
        // Sleep advice uses the published minimum. Three days is a product persistence filter,
        // not a diagnostic threshold. Use only actual observations for three consecutive dates.
        if let target = sleepTarget(profile: profile) {
            let nights = unique(observations.filter { $0.metric == .sleep && $0.day <= anchorDay
                && $0.day >= shift(anchorDay, by: -2) })
            if nights.count == 3, nights.allSatisfy({ $0.verified && $0.use == .estimate && isPlausible($0) && $0.value < target.lower }),
               Set(nights.map(\.channel)).count == 1 {
                insights.append(Insight(kind: .sleepOpportunity, metric: .sleep, direction: .below, observationCount: 3))
            }
        }
        // Correlated cardiovascular findings share one card, rather than duplicating the same event.
        for metric in [Metric.restingHR, .hrv, .respiration, .skinTemperature] {
            let days = (-2...0).map { shift(anchorDay, by: $0) }
            let recent = days.map { day in
                reading(metric: metric, observations: observations, anchorDay: day, profile: profile,
                        resetDay: metric == .hrv ? hrvResetDay : recoveryResetDay)
            }
            if let first = recent.first, first.state == .above || first.state == .below,
               zip(days, recent).allSatisfy({ $0.1.observation?.day == $0.0 && $0.1.basis == .personal && $0.1.state == first.state }),
               Set(recent.compactMap { $0.observation?.channel }).count == 1 {
                insights.append(Insight(kind: .sustainedChange, metric: metric, direction: first.state, observationCount: 3))
                break
            }
        }
        let covered = Set(insights.map(\.metric))
        for comparison in comparisons where !covered.contains(comparison.metric) {
            guard let delta = comparison.delta else { continue }
            // Display-resolution floors, not significance or clinical thresholds.
            let floor: Double
            switch comparison.metric {
            case .sleep, .bedtime: floor = 15
            case .restingHR, .hrv: floor = 2
            case .respiration: floor = 0.5
            case .skinTemperature: floor = 0.2
            case .effort: floor = 10
            }
            guard abs(delta) >= floor else { continue }
            // A second cardiovascular weekly card would repeat the sustained-change finding.
            if insights.contains(where: { $0.kind == .sustainedChange }),
               [.restingHR, .hrv, .respiration, .skinTemperature].contains(comparison.metric) { continue }
            insights.append(Insight(kind: .weeklyChange, metric: comparison.metric,
                                    direction: delta > 0 ? .above : .below,
                                    observationCount: comparison.recent.count + comparison.previous.count))
            if insights.count == 3 { break }
        }
        return Snapshot(anchorDay: anchorDay, readings: readings, comparisons: comparisons, insights: Array(insights.prefix(3)))
    }

    public static func isPlausible(_ row: Observation) -> Bool {
        guard row.value.isFinite else { return false }
        if let cfg = row.metric.configuration { return (cfg.minVal...cfg.maxVal).contains(row.value) }
        switch row.metric {
        case .sleep: return (0...1440).contains(row.value)
        case .effort: return (0...100).contains(row.value)
        case .bedtime: return (0..<1440).contains(row.value)
        default: return false
        }
    }

    private static func unique(_ rows: [Observation]) -> [Observation] {
        let groups = Dictionary(grouping: rows.filter { validDay($0.day) }, by: \.day)
        return groups.values.compactMap { values in
            let distinct = Set(values)
            return distinct.count == 1 ? distinct.first : nil
        }.sorted { $0.day < $1.day }
    }

    public static func shift(_ day: String, by offset: Int) -> String {
        let formatter = dayFormatter()
        guard let date = formatter.date(from: day), formatter.string(from: date) == day,
              let shifted = utcCalendar.date(byAdding: .day, value: offset, to: date) else { return "" }
        return formatter.string(from: shifted)
    }
    private static func validDay(_ day: String) -> Bool { !shift(day, by: 0).isEmpty }
    private static func days(from start: String, through end: String) -> [String] {
        guard start <= end, validDay(start), validDay(end) else { return [] }
        var result: [String] = [], day = start
        while day <= end && result.count < 181 { result.append(day); day = shift(day, by: 1) }
        return result
    }
    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private static func dayFormatter() -> DateFormatter {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = utcCalendar; formatter.timeZone = utcCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        return formatter
    }
}
