import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The local model selects approved statements; generated prose never becomes health guidance.
enum LocalMetricExplanation {
    struct Result: Sendable {
        let text: String?
        let status: String
    }

    static func select(statements: [String]) async -> Result {
        let fallback = statements.prefix(3).joined(separator: "\n\n")
        guard !statements.isEmpty else {
            return Result(text: nil, status: String(localized: "No comparisons to explain yet."))
        }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.availability == .available, model.supportsLocale() else {
                return Result(text: fallback, status: String(localized: "Apple Intelligence is unavailable for this device, language or setting. Showing the standard explanation."))
            }
            do {
                try Task.checkCancellation()
                let session = LanguageModelSession(model: model, instructions: "Select up to three distinct statement IDs that best explain these comparisons and their measurement limits. Return only IDs from the list. Do not diagnose, infer facts or create advice.")
                let prompt = statements.prefix(6).enumerated().map { "s\($0.offset): \($0.element)" }.joined(separator: "\n")
                let response = try await session.respond(to: prompt, generating: Selection.self,
                    options: GenerationOptions(temperature: 0, maximumResponseTokens: 128))
                try Task.checkCancellation()
                let allowed = Dictionary(uniqueKeysWithValues: statements.prefix(6).enumerated().map { ("s\($0.offset)", $0.element) })
                let ids = response.content.statementIDs
                guard !ids.isEmpty, ids.count <= 3, Set(ids).count == ids.count,
                      ids.allSatisfy({ allowed[$0] != nil }) else {
                    return Result(text: fallback, status: String(localized: "Showing the standard explanation."))
                }
                return Result(text: ids.compactMap { allowed[$0] }.joined(separator: "\n\n"),
                              status: String(localized: "Selected on device from verified explanation text."))
            } catch {
                return Result(text: fallback, status: String(localized: "Showing the standard explanation."))
            }
        }
        #endif
        return Result(text: fallback, status: String(localized: "On-device explanations require iOS 26 or later and Apple Intelligence. Showing the standard explanation."))
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
private struct Selection {
    @Guide(description: "One to three distinct IDs from the supplied statements, such as s0.")
    var statementIDs: [String]
}
#endif
