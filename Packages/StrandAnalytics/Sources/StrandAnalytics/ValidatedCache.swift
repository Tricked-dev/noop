import Foundation

/// Disposable intermediate results, never authoritative health data. Consumers additionally
/// validate the current raw-input witness before using an entry from a previous process.
public struct ValidatedCache<Payload: Codable>: Codable {
    private let version: Int
    private let build: String
    private let configuration: String
    private let created: Date
    private let payload: Payload

    public init(build: String, configuration: String, payload: Payload, now: Date = Date()) {
        version = 1; self.build = build; self.configuration = configuration
        self.payload = payload; created = now
    }

    public func value(build: String, configuration: String, now: Date = Date()) -> Payload? {
        guard version == 1, self.build == build, self.configuration == configuration,
              now.timeIntervalSince(created) >= 0, now.timeIntervalSince(created) <= 30 * 86400 else { return nil }
        return payload
    }
}
