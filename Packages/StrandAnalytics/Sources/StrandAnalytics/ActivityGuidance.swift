import Foundation

/// Descriptive comparisons and adult guidance. Missing records are never zero activity.
public enum ActivityGuidance {
    public struct Point: Equatable, Sendable {
        public let day: String
        public let value: Double
        public let channel: String
        public init(day: String, value: Double, channel: String) {
            self.day = day; self.value = value; self.channel = channel
        }
    }
    public struct Comparison: Equatable, Sendable {
        public let previous: Double?
        public let recent: Double?
        public let previousCount: Int
        public let recentCount: Int
        public let compatible: Bool
        public var delta: Double? {
            guard compatible, let previous, let recent else { return nil }
            return recent - previous
        }
    }
    /// Two completed seven-day windows; five distinct valid days each. Daily averages, never totals.
    /// Reject conflicting duplicates, unknown/mixed sources, negative and non-finite values.
    public static func compare(_ points: [Point], anchorDay: String) -> Comparison {
        let start = MetricContext.shift(anchorDay, by: -14)
        let split = MetricContext.shift(anchorDay, by: -7)
        let grouped = Dictionary(grouping: points.filter {
            $0.day >= start && $0.day < anchorDay && !$0.channel.isEmpty && $0.value.isFinite
                && $0.value >= 0 && $0.value <= Double(Int32.max)
                && MetricContext.shift($0.day, by: 0) == $0.day
        }, by: \.day)
        let valid = grouped.values.compactMap { rows -> Point? in
            guard let first = rows.first, rows.allSatisfy({ $0 == first }) else { return nil }
            return first
        }
        let previous = valid.filter { $0.day < split }, recent = valid.filter { $0.day >= split }
        let compatible = !start.isEmpty && Set(valid.map(\.channel)).count == 1
        func mean(_ rows: [Point]) -> Double? {
            guard rows.count >= 5, compatible else { return nil }
            let result = rows.reduce(0) { $0 + $1.value / Double(rows.count) }
            return result.isFinite ? result : nil
        }
        return Comparison(previous: mean(previous), recent: mean(recent),
                          previousCount: previous.count, recentCount: recent.count, compatible: compatible)
    }
    public enum Walking: Sendable { case insufficient, lower, maintained }
    /// Ten percent is a product noise filter, not a clinical cutoff or an optimal activity target.
    public static func walking(_ comparison: Comparison) -> Walking {
        guard comparison.delta != nil, let a = comparison.previous, let b = comparison.recent, a > 0 else { return .insufficient }
        return b < a * 0.9 ? .lower : .maintained
    }
    /// WHO 2020 equivalent moderate minutes: 1 vigorous minute counts as 2 moderate minutes.
    /// Inputs are explicitly reported aerobic minutes, never inferred from sport, strain or HR zones.
    public static func equivalentMinutes(moderate: Double?, vigorous: Double?, confirmedAge: Int?) -> Double? {
        guard let age = confirmedAge, (18...120).contains(age), let moderate, let vigorous,
              moderate.isFinite, vigorous.isFinite, moderate >= 0, vigorous >= 0,
              moderate + vigorous <= 7 * 24 * 60 else { return nil }
        return moderate + 2 * vigorous
    }
    public static func strengthDays(_ days: [String], anchorDay: String) -> Int {
        let start = MetricContext.shift(anchorDay, by: -7)
        guard !start.isEmpty else { return 0 }
        return Set(days.filter { $0 >= start && $0 < anchorDay && MetricContext.shift($0, by: 0) == $0 }).count
    }
    public static func isStrengthSport(_ key: String) -> Bool {
        ["strength", "bodybuilding", "weightlifting", "traditionalstrengthtraining",
         "functionalstrengthtraining", "strengthtraining", "weighttraining"].contains(key)
    }
}
