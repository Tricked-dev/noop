import SwiftUI
import StrandAnalytics
import StrandDesign

/// Catalog-wide evidence is reachable both from context and from each metric's detail screen.
struct MetricEvidenceCard: View {
    let metric: MetricDescriptor
    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Text("Accuracy & interpretation").font(StrandFont.headline)
                Text(metric.sourceLabel).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                Text(MetricEvidenceCopy.explanation(metric.key)).font(StrandFont.subhead)
                ForEach(MetricEvidence.references(for: MetricEvidence.group(for: metric.key)), id: \.self) { reference in
                    if let url = URL(string: reference) {
                        Link(destination: url) {
                            Text("Research and applicability").font(StrandFont.caption)
                        }
                    }
                }
            }.foregroundStyle(StrandPalette.textPrimary)
        }
    }
}

struct MetricEvidenceCatalog: View {
    let anchorDay: String
    private var metrics: [MetricDescriptor] { MetricCatalog.all.filter { $0.source != "xiaomi-band" } }
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
            Text("All metrics: evidence & comparisons").font(StrandFont.title2)
            Text("Research on a device is not validation of every app using it. These entries include imported data and calculated scores; availability depends on your sources.")
                .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            ForEach(metrics) { metric in
                CatalogEvidenceRow(metric: metric, anchorDay: anchorDay)
            }
        }
    }
}

private struct CatalogEvidenceRow: View {
    let metric: MetricDescriptor
    let anchorDay: String
    @State private var expanded = false
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            if expanded {
                    MetricEvidenceCard(metric: metric)
                    if MetricEvidence.allowsGenericComparison(metric.key) {
                        CatalogMetricComparison(metric: metric, anchorDay: anchorDay)
                    }
            }
        } label: {
            Text(metric.title + " · " + metric.sourceLabel).font(StrandFont.subhead)
        }
    }
}

private struct CatalogMetricComparison: View {
    let metric: MetricDescriptor
    let anchorDay: String
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.systemKey) private var systemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    @AppStorage(UnitPrefs.effortScaleKey) private var effortRaw = EffortScale.hundred.rawValue
    @AppStorage("metricContext.localExplanation") private var useLocalExplanation = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var comparison: ActivityGuidance.Comparison?
    @State private var explanation: String?
    @State private var generation: Task<Void, Never>?
    private var identity: String { "\(metric.id):\(anchorDay):\(repo.deviceId):\(repo.refreshSeq)" }
    private func format(_ value: Double) -> String {
        let system = UnitSystem(rawValue: systemRaw) ?? .metric
        return metric.format(value, system: system,
                             temperature: UnitPrefs.resolveTemperature(system: system, override: temperatureRaw),
                             effortScale: UnitPrefs.resolveEffortScale(effortRaw))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Text("Two completed weeks · daily averages").font(StrandFont.subhead)
            Text(MetricContext.shift(anchorDay, by: -14) + " – " + MetricContext.shift(anchorDay, by: -8))
                .font(StrandFont.caption)
            Text(comparison?.previous.map(format) ?? "—")
            Text(MetricContext.shift(anchorDay, by: -7) + " – " + MetricContext.shift(anchorDay, by: -1))
                .font(StrandFont.caption)
            Text(comparison?.recent.map(format) ?? "—")
            Text("Requires five recorded days in each week and one consistent source. These averages describe records, not healthy targets or proof of improvement.")
                .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            if useLocalExplanation, let a = comparison?.previous, let b = comparison?.recent {
                Button(String(localized: "Explain these comparisons")) {
                    generation?.cancel(); explanation = nil
                    let facts = [metric.title + ": " + MetricEvidenceCopy.explanation(metric.key),
                                 MetricContext.shift(anchorDay, by: -14) + " – " + MetricContext.shift(anchorDay, by: -8) + ": " + format(a),
                                 MetricContext.shift(anchorDay, by: -7) + " – " + MetricContext.shift(anchorDay, by: -1) + ": " + format(b)]
                    generation = Task {
                        let result = await LocalMetricExplanation.select(statements: facts)
                        guard !Task.isCancelled else { return }
                        explanation = result.text
                    }
                }
                if let explanation { Text(explanation).font(StrandFont.subhead) }
            }
        }
        .task(id: identity) {
            generation?.cancel(); explanation = nil; comparison = nil
            let points = await repo.contextSeries(key: metric.key, source: metric.source, anchorDay: anchorDay)
            guard !Task.isCancelled else { return }
            comparison = ActivityGuidance.compare(points, anchorDay: anchorDay)
        }
        .onChange(of: useLocalExplanation) { _, enabled in if !enabled { generation?.cancel(); explanation = nil } }
        .onChange(of: systemRaw) { _, _ in generation?.cancel(); explanation = nil }
        .onChange(of: temperatureRaw) { _, _ in generation?.cancel(); explanation = nil }
        .onChange(of: effortRaw) { _, _ in generation?.cancel(); explanation = nil }
        .onChange(of: scenePhase) { _, phase in if phase != .active { generation?.cancel() } }
        .onDisappear { generation?.cancel() }
    }
}
