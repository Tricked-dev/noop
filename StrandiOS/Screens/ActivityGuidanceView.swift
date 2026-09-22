import SwiftUI
import StrandAnalytics
import StrandDesign

struct ActivityGuidanceView: View {
    let anchorDay: String
    let confirmedAge: Int?
    let bedtime: MetricContext.Comparison?
    @EnvironmentObject private var repo: Repository
    @State private var steps: ActivityGuidance.Comparison?
    @State private var strengthDays: Int?
    @State private var explanation: String?
    @State private var generation: Task<Void, Never>?
    @AppStorage("metricContext.localExplanation") private var useLocalExplanation = false
    @Environment(\.scenePhase) private var scenePhase
    private var identity: String { "\(anchorDay):\(repo.deviceId):\(repo.refreshSeq)" }
    private var adult: Bool { confirmedAge.map { (18...120).contains($0) } ?? false }
    private var walkingText: String {
        switch steps.map(ActivityGuidance.walking) ?? .insufficient {
        case .lower: return String(localized: "Recorded Apple Health steps were lower this week. If carrying and wear were similar, consider a manageable extra walk. Start gradually; there is no universal 10,000-step requirement.")
        case .maintained: return String(localized: "Your recorded Apple Health step volume was maintained this week. Keep a routine that feels sustainable; more is not always the next goal.")
        case .insufficient: return String(localized: "More consistent Apple Health step records are needed for walking advice. WHOOP 4 motion estimates are shown as trends, not precise step targets.")
        }
    }
    private var strengthText: String {
        guard let strengthDays else { return String(localized: "No comparable reading") }
        let count = String(localized: "Strength sessions recorded on \(strengthDays) days in the last completed seven days.")
        return count + " " + (strengthDays >= 2
            ? String(localized: "You recorded strength work on at least two days. Keep it sustainable and check that your routine covers all major muscle groups.")
            : String(localized: "If your log is complete, consider planning strength work on two days, covering all major muscle groups. Missing logs do not prove inactivity."))
    }
    private var sleepText: String {
        if let bedtime, let delta = bedtime.delta, delta <= -15 {
            return String(localized: "Your recorded bedtimes varied less this week. Keep a schedule that works for you; this does not prove better sleep quality.")
        }
        return String(localized: "Try consistent bed and wake times. Check recorded sleep timing first: WHOOP 4's sparse motion can mistake quiet wakefulness for sleep. Bedtime variation is not the clinical Sleep Regularity Index.")
    }
    private var movementText: String {
        String(localized: "If you have been sitting for a while, take a comfortable movement break when practical. Strap stillness cannot establish sitting or desk work; no exact break interval is inferred.")
    }
    private var statements: [String] { adult ? [walkingText, strengthText, sleepText, movementText] : [sleepText, movementText] }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
            Text("Activity & habits").font(StrandFont.title2)
            if adult {
                NoopCard {
                    VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                        Text(walkingText).font(StrandFont.subhead)
                        if let a = steps?.previous, let b = steps?.recent {
                            Text(String(localized: "Recorded daily step averages: \(Int(a.rounded())) → \(Int(b.rounded()))"))
                                .font(StrandFont.caption)
                        }
                        Link("Research and applicability", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/40713949/")!)
                    }
                }
                NoopCard { Text(strengthText).font(StrandFont.subhead) }
                AerobicWeekReview(anchorDay: anchorDay, confirmedAge: confirmedAge)
                    .id(anchorDay)
            }
            NoopCard {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    Text(sleepText)
                    Link("Research and applicability", destination: URL(string: "https://www.cdc.gov/sleep/about/")!)
                    Text(movementText)
                    Link("Research and applicability", destination: URL(string: "https://www.who.int/publications/i/item/9789240015128")!)
                }.font(StrandFont.subhead)
            }
            if useLocalExplanation {
                Button(String(localized: "Explain activity & habits")) {
                    generation?.cancel(); explanation = nil
                    let facts = statements
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
            generation?.cancel(); explanation = nil; steps = nil; strengthDays = nil
            let points = await repo.contextSeries(key: "steps", source: "apple-health", anchorDay: anchorDay)
            let days = await repo.contextStrengthDays(anchorDay: anchorDay)
            guard !Task.isCancelled else { return }
            steps = ActivityGuidance.compare(points, anchorDay: anchorDay)
            strengthDays = days.map { ActivityGuidance.strengthDays($0, anchorDay: anchorDay) }
        }
        .onChange(of: statements) { _, _ in generation?.cancel(); explanation = nil }
        .onChange(of: useLocalExplanation) { _, enabled in if !enabled { generation?.cancel(); explanation = nil } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { generation?.cancel() } }
        .onDisappear { generation?.cancel() }
    }
}

/// A local weekly review supplies intensity that existing imported workout rows do not record.
/// Separate date-window keys prevent a previous week's entered minutes becoming current advice.
private struct AerobicWeekReview: View {
    let anchorDay: String
    let confirmedAge: Int?
    @AppStorage private var moderate: String
    @AppStorage private var vigorous: String
    init(anchorDay: String, confirmedAge: Int?) {
        self.anchorDay = anchorDay; self.confirmedAge = confirmedAge
        _moderate = AppStorage(wrappedValue: "", "metricContext.aerobic.\(anchorDay).moderate")
        _vigorous = AppStorage(wrappedValue: "", "metricContext.aerobic.\(anchorDay).vigorous")
    }
    private var equivalent: Double? {
        ActivityGuidance.equivalentMinutes(moderate: Int(moderate).map(Double.init),
                                          vigorous: Int(vigorous).map(Double.init), confirmedAge: confirmedAge)
    }
    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Text("Weekly aerobic activity").font(StrandFont.headline)
                Text(MetricContext.shift(anchorDay, by: -7) + " – " + MetricContext.shift(anchorDay, by: -1))
                    .font(StrandFont.caption)
                Text("Adult guidance: 150–300 moderate or 75–150 vigorous aerobic minutes per week, or an equivalent mix. Some activity is better than none; build up gradually.")
                Text("Workouts and HR zones do not establish intensity. Optionally enter your actual aerobic minutes for these dates, including unlogged activity; enter 0 only when you know there was none. Saved on this device.")
                TextField(String(localized: "Moderate minutes"), text: $moderate).keyboardType(.numberPad)
                TextField(String(localized: "Vigorous minutes"), text: $vigorous).keyboardType(.numberPad)
                Text("Talk test: moderate activity allows talking but not singing; vigorous activity allows only a few words before pausing for breath.")
                    .font(StrandFont.caption)
                if let equivalent {
                    Text(String(localized: "Reported moderate-equivalent minutes: \(Int(equivalent.rounded()))"))
                    Text(equivalent >= 150
                        ? String(localized: "Your reported activity reaches the adult weekly minimum. Maintain a sustainable routine; this is based on your entries, not sensor verification.")
                        : String(localized: "Your entries are below the adult weekly minimum. If this review is complete, consider adding manageable activity over time."))
                } else if !moderate.isEmpty || !vigorous.isEmpty {
                    Text("Enter both totals as non-negative minutes for this seven-day window.")
                }
                Link("Research and applicability", destination: URL(string: "https://www.who.int/publications/i/item/9789240015128")!)
                Link("Talk test", destination: URL(string: "https://www.cdc.gov/physical-activity-basics/measuring/index.html")!)
            }.font(StrandFont.subhead)
        }
    }
}
