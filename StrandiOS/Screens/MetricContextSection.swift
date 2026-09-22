import SwiftUI
import StrandAnalytics
import StrandDesign
import WhoopProtocol
import WhoopStore

struct MetricContextSection: View {
    let anchorDay: String
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let registry = model.deviceRegistry {
            MetricContextContent(anchorDay: anchorDay, registry: registry)
        }
    }
}

private struct MetricContextContent: View {
    let anchorDay: String
    @ObservedObject var registry: DeviceRegistry
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("metricContext.confirmedDOB") private var confirmedDOB = 0.0
    @AppStorage("metricContext.localExplanation") private var useLocalExplanation = false
    @AppStorage(UnitPrefs.hrvWindowKey) private var hrvWindow = HrvWindow.whole.rawValue
    @AppStorage(Baselines.hrvBaselineEpochKey) private var hrvReset = 0.0
    @AppStorage(Baselines.recoveryBaselineEpochKey) private var recoveryReset = 0.0
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    @State private var snapshot: MetricContext.Snapshot?
    @State private var showDetails = false
    @State private var explanation: String?
    @State private var generation: Task<Void, Never>?
    @State private var generationID = UUID()
    @State private var generating = false
    @State private var aiStatus: String?

    private struct Input: Equatable {
        let rows: [SourcedDailyMetric]
        let sleeps: [CachedSleepSession]
        let day: String
        let device: String
        let model: String?
        let brand: String?
        let profile: MetricContext.Profile
        let hrvWindow: String
        let hrvReset: Double
        let recoveryReset: Double
        let refresh: Int
    }
    private var input: Input {
        let device = registry.devices.first { $0.id == registry.activeDeviceId }
        let cutoff = MetricContext.shift(anchorDay, by: -180)
        let components = anchorDay.split(separator: "-").compactMap { Int($0) }
        let anchorDate = components.count == 3 ? Calendar.current.date(from:
            DateComponents(year: components[0], month: components[1], day: components[2], hour: 12)) : nil
        let age = anchorDate.map { ProfileStore.years(from: profile.dateOfBirth, to: $0) }
        return Input(rows: repo.vitalMetricRows.filter { $0.metric.day >= cutoff && $0.metric.day <= anchorDay },
                     sleeps: repo.sleeps, day: anchorDay, device: registry.activeDeviceId,
                     model: device?.model, brand: device?.brand,
                     profile: .init(confirmedAge: confirmedDOB == profile.dateOfBirth.timeIntervalSince1970 ? age : nil,
                                    sex: profile.sex, heightCM: profile.heightCm),
                     hrvWindow: hrvWindow, hrvReset: hrvReset, recoveryReset: recoveryReset,
                     refresh: repo.refreshSeq)
    }
    private var isWhoop4: Bool {
        let device = registry.devices.first { $0.id == registry.activeDeviceId }
        return device?.model != nil && DeviceFamily.forRegistryDevice(model: device?.model, brand: device?.brand) == .whoop4
    }
    private var temperature: TemperatureUnit {
        UnitPrefs.resolveTemperature(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric, override: temperatureRaw)
    }

    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                Text("Your ranges & insights")
                    .font(StrandFont.headline)
                if isWhoop4 {
                    Text("WHOOP 4: HRV, sleep, skin temperature, calories and scores are best used for trends. Raw oxygen and respiration fields are uncalibrated.")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
                if let snapshot {
                    ForEach(snapshot.readings.filter { [.restingHR, .hrv, .sleep].contains($0.metric) }) { reading in
                        compactReading(reading)
                    }
                    if !snapshot.insights.isEmpty {
                        Divider()
                        ForEach(snapshot.insights) { insight in
                            Text(insightText(insight, snapshot: snapshot))
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                    }
                } else {
                    ProgressView()
                }
                Button { showDetails = true } label: {
                    Label(String(localized: "Ranges, evidence & weekly comparisons"), systemImage: "chart.bar.xaxis")
                        .font(StrandFont.subhead)
                }
                .accessibilityHint(Text("Open the readings, their reliability and the research behind comparisons."))
            }
            .foregroundStyle(StrandPalette.textPrimary)
        }
        .task(id: input) { await load(input) }
        .sheet(isPresented: $showDetails) { details }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cancelGeneration() } }
        .onChange(of: showDetails) { _, visible in if !visible { cancelGeneration() } }
        .onChange(of: useLocalExplanation) { _, enabled in
            if !enabled { cancelGeneration(); explanation = nil }
        }
        .onDisappear { cancelGeneration() }
    }

    private var details: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                    Text(anchorDay).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    Text("A usual range describes your history, not a diagnosis or a healthy target.")
                        .font(StrandFont.subhead)
                    if input.profile.confirmedAge == nil {
                        NoopCard {
                            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                                Text("Confirm your profile age before using age-based sleep guidance.")
                                Text(String(localized: "Profile age: \(profile.age)"))
                                Button(String(localized: "This age is correct")) {
                                    confirmedDOB = profile.dateOfBirth.timeIntervalSince1970
                                }
                                Text("If it is incorrect, edit your date of birth in Profile first.")
                                    .font(StrandFont.caption)
                            }.font(StrandFont.subhead)
                        }
                    }
                    if isWhoop4 { hardwareGuide }
                    if let snapshot {
                        ForEach(snapshot.readings) { reading in
                            NoopCard {
                                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                                    compactReading(reading)
                                    rangeBar(reading)
                                    Text(evidenceText(reading)).font(StrandFont.caption)
                                        .foregroundStyle(StrandPalette.textSecondary)
                                    Text(metricExplanation(reading.metric)).font(StrandFont.subhead)
                                    referenceLinks(reading.metric)
                                }
                            }
                        }
                        Text("Weekly comparisons").font(StrandFont.title2)
                        Text("Two completed weeks. Averages need at least five recorded days per week; effort totals need all seven. Differences are descriptive, not proof of improvement.")
                            .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                        ForEach(snapshot.comparisons) { comparison in
                            NoopCard {
                                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                                    Text(title(comparison.metric)).font(StrandFont.headline)
                                    Text(weekText(comparison.previous, metric: comparison.metric))
                                    Text(weekText(comparison.recent, metric: comparison.metric))
                                    Text(comparisonText(comparison)).foregroundStyle(StrandPalette.textSecondary)
                                }.font(StrandFont.subhead)
                            }
                        }
                        localExplanation(snapshot)
                        ActivityGuidanceView(anchorDay: anchorDay, confirmedAge: input.profile.confirmedAge,
                                             bedtime: snapshot.comparisons.first { $0.metric == .bedtime })
                    }
                    MetricEvidenceCatalog(anchorDay: anchorDay)
                }
                .padding(NoopMetrics.screenPadding)
                .foregroundStyle(StrandPalette.textPrimary)
            }
            .background(StrandPalette.surfaceBase)
            .navigationTitle(Text("Your context"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { showDetails = false }
                }
            }
        }
    }

    private func compactReading(_ reading: MetricContext.Reading) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            HStack(alignment: .firstTextBaseline) {
                Text(title(reading.metric)).font(StrandFont.subhead)
                Spacer(minLength: NoopMetrics.space2)
                Text(reading.state == .unverified ? "—" : reading.observation.map { format($0.value, metric: reading.metric) } ?? "—")
                    .font(StrandFont.headline)
            }
            Text(rangeText(reading)).font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
            Text(reliabilityText(reading)).font(StrandFont.caption)
                .foregroundStyle(reading.state == .unverified ? StrandPalette.statusWarning : StrandPalette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func rangeBar(_ reading: MetricContext.Reading) -> some View {
        if let lo = reading.lower, let hi = reading.upper, let value = reading.observation?.value,
           reading.state != .unverified, reading.state != .stale {
            let padding = max((hi - lo) / 2, 1)
            let start = min(lo, value) - padding, end = max(hi, value) + padding
            TypicalRangeBar(value: (value - start) / (end - start),
                            typical: ((lo - start) / (end - start))...((hi - start) / (end - start)),
                            color: StrandPalette.accent)
                .accessibilityHidden(true)
        }
    }

    private var hardwareGuide: some View {
        NoopCard(tint: StrandPalette.statusWarning) {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Text("WHOOP 4: how to use these values").font(StrandFont.headline)
                Text("Heart rate: an optical estimate in bpm. Movement and fit can affect it; this is not an ECG.")
                Text("HRV: use your own trend with the same source and method. Readings flagged for R–R over-counting are withheld from comparisons.")
                Text("Skin temperature: provisional conversion. Use trends only, not the absolute temperature or a fever threshold.")
                Text("Sleep duration, stages, calories, effort and recovery: algorithm estimates. Look for patterns; precise totals and scores are not clinical measurements. Sparse sleep is excluded from advice.")
                Text("Fitness/Body Age and VO₂max are model estimates, not measured age or fitness.")
                Text("Steps and distance: motion-based estimates; use trends, not precise totals.")
                Text("Raw SpO₂ and respiration-adjacent fields are uncalibrated. They are not oxygen percentages or breaths per minute and should not guide health decisions.")
                Text("Imported WHOOP and Apple Health readings keep their own source and measurement limits.")
            }.font(StrandFont.subhead)
        }
    }

    private func load(_ input: Input) async {
        cancelGeneration(); explanation = nil; snapshot = nil
        let observations = await repo.metricContextObservations(anchorDay: input.day,
            whoop4: input.model != nil && DeviceFamily.forRegistryDevice(model: input.model, brand: input.brand) == .whoop4,
            knownDevice: input.model != nil, hrvWindow: input.hrvWindow)
        guard !Task.isCancelled else { return }
        func resetDay(_ epoch: Double) -> String? {
            epoch > 0 ? Repository.localDayKey(Date(timeIntervalSince1970: epoch)) : nil
        }
        let hrv = resetDay(input.hrvReset), recovery = resetDay(input.recoveryReset)
        let task = Task.detached(priority: .utility) {
            MetricContext.evaluate(observations: observations, anchorDay: input.day, profile: input.profile,
                                   hrvResetDay: hrv, recoveryResetDay: recovery)
        }
        let result = await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
        guard !Task.isCancelled else { return }
        snapshot = result
    }

    private func title(_ metric: MetricContext.Metric) -> String {
        switch metric {
        case .restingHR: return String(localized: "Resting heart rate")
        case .hrv: return String(localized: "Heart rate variability")
        case .respiration: return String(localized: "Respiratory rate")
        case .skinTemperature: return String(localized: "Skin temperature")
        case .sleep: return String(localized: "Sleep duration")
        case .effort: return String(localized: "Effort")
        case .bedtime: return String(localized: "Bedtime variation")
        }
    }
    private func format(_ value: Double, metric: MetricContext.Metric, delta: Bool = false) -> String {
        guard value.isFinite else { return "—" }
        switch metric {
        case .sleep, .bedtime:
            return String(localized: "\(Int(value.rounded())) min")
        case .skinTemperature:
            return delta ? UnitFormatter.temperatureDeltaFromCelsius(value, unit: temperature, decimals: 1)
                : UnitFormatter.temperatureFromCelsius(value, unit: temperature, decimals: 1)
        case .hrv: return String(format: "%.1f ms", value)
        case .restingHR: return String(format: "%.1f bpm", value)
        case .respiration: return String(format: "%.1f rpm", value)
        case .effort: return String(format: "%.1f", value)
        }
    }
    private func rangeText(_ reading: MetricContext.Reading) -> String {
        if let lo = reading.lower {
            let lower = format(lo, metric: reading.metric)
            let bounds = reading.upper.map { lower + " – " + format($0, metric: reading.metric) }
                ?? String(localized: "At least \(lower)")
            if reading.basis == .recommendation {
                if reading.state != .descriptive {
                    return stateText(reading.state) + " · " + String(localized: "Age-based recommendation: \(bounds)")
                }
                return String(localized: "Age-based recommendation: \(bounds)")
            }
            let state = stateText(reading.state)
            return String(localized: "\(state) · Your usual range: \(bounds)")
        }
        if reading.state == .learning {
            return String(localized: "Learning your range: \(reading.nights) of 14 valid prior nights")
        }
        return stateText(reading.state)
    }
    private func stateText(_ state: MetricContext.State) -> String {
        switch state {
        case .below: return String(localized: "Below")
        case .within: return String(localized: "Within")
        case .above: return String(localized: "Above")
        case .stale: return String(localized: "History or reading is too old for a current comparison")
        case .unverified: return String(localized: "Unverified — excluded from comparisons")
        case .missing: return String(localized: "No comparable reading")
        case .learning: return String(localized: "Learning your range")
        case .descriptive: return String(localized: "Descriptive estimate; no personal range")
        }
    }
    private func reliabilityText(_ reading: MetricContext.Reading) -> String {
        guard let row = reading.observation else { return "" }
        let use: String
        switch row.use {
        case .estimate: use = String(localized: "Estimate")
        case .trendOnly: use = String(localized: "Trends only — avoid absolute-value judgments")
        case .unverified: use = String(localized: "Uncalibrated or unverified")
        }
        return row.day + " · " + use
    }
    private func evidenceText(_ reading: MetricContext.Reading) -> String {
        guard let row = reading.observation else { return "" }
        var text = row.channel.components(separatedBy: ":").dropFirst().joined(separator: " · ")
        if let start = reading.referenceStart, let end = reading.referenceEnd {
            text += "\n" + String(localized: "Reference: \(start) to \(end) · \(reading.nights) valid nights")
        }
        return text
    }
    private func metricExplanation(_ metric: MetricContext.Metric) -> String {
        switch metric {
        case .hrv: return String(localized: "HRV depends on measurement method and recording duration. Age charts from five-minute ECGs are not applied to overnight wearable readings.")
        case .sleep: return String(localized: "Adults aged 18–60 are advised to regularly sleep at least seven hours. Height and sex do not change this recommendation. An estimated short night is not proof of sleep deprivation.")
        case .skinTemperature: return String(localized: "Wrist temperature is not core temperature. A change from your own history is more useful than comparing it with a fever threshold.")
        case .effort: return String(localized: "Effort is a NOOP score on a 0–100 scale. Weekly totals describe recorded load; they do not predict injury or define safe training.")
        default: return String(localized: "This comparison uses prior readings from a consistent source. A single unusual value does not establish a health problem.")
        }
    }
    @ViewBuilder private func referenceLinks(_ metric: MetricContext.Metric) -> some View {
        let url: String? = metric == .sleep ? "https://www.cdc.gov/sleep/about/"
            : metric == .hrv ? "https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0118308"
            : metric == .effort ? "https://pubmed.ncbi.nlm.nih.gov/32502973/"
            : metric == .restingHR ? "https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0227709" : nil
        if let url, let destination = URL(string: url) {
            Link(destination: destination) {
                Text("Research and applicability").font(StrandFont.caption)
            }
        }
    }
    private func weekText(_ week: MetricContext.Week, metric: MetricContext.Metric) -> String {
        let value = week.value.map { format($0, metric: metric) } ?? "—"
        return String(localized: "\(week.start) to \(week.end): \(value) · \(week.count)/7 days")
    }
    private func comparisonText(_ comparison: MetricContext.Comparison) -> String {
        guard let delta = comparison.delta else {
            return String(localized: "Not enough comparable data in both weeks")
        }
        let change = (delta > 0 ? "+" : "") + format(delta, metric: comparison.metric, delta: true)
        return String(localized: "Change: \(change)")
    }
    private func insightText(_ insight: MetricContext.Insight, snapshot: MetricContext.Snapshot) -> String {
        let metric = title(insight.metric)
        switch insight.kind {
        case .sleepOpportunity:
            return String(localized: "Three recorded nights were below your age-based sleep recommendation. Consider allowing more time for sleep.")
        case .sustainedChange:
            return String(localized: "\(metric) has been outside your usual range for three recorded days. Review the trend and how you feel; this does not identify a cause.")
        case .weeklyChange:
            guard let comparison = snapshot.comparisons.first(where: { $0.metric == insight.metric }) else { return "" }
            return metric + ": " + comparisonText(comparison)
        }
    }

    private func localExplanation(_ snapshot: MetricContext.Snapshot) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Toggle(String(localized: "On-device explanation preview"), isOn: $useLocalExplanation)
                Text("Optional Apple Intelligence. Runs on this device when requested. Calculations and advice stay the same.")
                    .font(StrandFont.caption)
                if useLocalExplanation {
                    Button(String(localized: "Explain these comparisons")) { explain(snapshot) }
                        .disabled(generating)
                    if generating { ProgressView() }
                    if let explanation { Text(explanation).font(StrandFont.subhead) }
                    if let aiStatus { Text(aiStatus).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary) }
                }
            }
        }
    }
    private func cancelGeneration() {
        generation?.cancel(); generation = nil; generationID = UUID(); generating = false
    }
    private func explain(_ snapshot: MetricContext.Snapshot) {
        cancelGeneration(); explanation = nil; aiStatus = nil
        let advice = snapshot.insights.map { insightText($0, snapshot: snapshot) }
        let weekly = snapshot.comparisons.filter { $0.delta != nil }.map {
            title($0.metric) + ": " + weekText($0.previous, metric: $0.metric) + "; "
                + weekText($0.recent, metric: $0.metric) + ". " + comparisonText($0)
        }
        let readings = snapshot.readings.filter { $0.observation != nil }.map {
            title($0.metric) + ": " + rangeText($0) + ". " + reliabilityText($0) + ". " + metricExplanation($0.metric)
        }
        let statements = Array(advice.prefix(2)) + Array(weekly.prefix(2)) + Array(readings.prefix(2))
        let id = UUID(); generationID = id; generating = true
        generation = Task {
            let result = await LocalMetricExplanation.select(statements: statements)
            guard !Task.isCancelled, generationID == id else { return }
            explanation = result.text; aiStatus = result.status; generating = false
        }
    }
}
