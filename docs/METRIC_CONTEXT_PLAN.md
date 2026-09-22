# Metric context, comparisons, and recommendations

Status: iOS metric context, catalog evidence and activity guidance are implemented. See `METRIC_CONTEXT_TESTING.md` for reproducible checks and `METRIC_EVIDENCE.md` for research coverage. Later unimplemented prototypes remain proposals.
Date: 2026-09-22.

## Objective

Make NOOP's measurements understandable by showing the relevant range, explaining changes,
and surfacing a small number of useful suggestions supported by the user's own data.
Deliver the feature on iOS, with the iPhone 15 Pro as the initial evaluation device and all
computation on-device. macOS feature adoption is a nice-to-have and does not block the iOS release.
Android implementation and validation are explicitly outside this plan's scope.

This is an intentional platform exception for this feature. Preserve existing shared Swift
behavior and keep the macOS app compiling when shared files change; that compatibility check
does not require delivering the new macOS UI. No Android files or parity work are planned.

This plan covers both requested areas: metric ranges and comparisons, and algorithmic
recommendations. The research assessment below informs both, with a distinction between
published findings and proposed NOOP implementation rules.

The first release adds interpretation and presentation. It does not change stored measurements,
Charge / Effort / Rest formulas, strap sampling, or BLE behavior. Recommendations require no
AI service, account, telemetry, or network access.

## Existing foundations

The following entry points were inspected while preparing the plan. Their presence is not evidence
that every calculation or recommendation is suitable for reuse without review.

| Area | Existing implementation | Planned use |
| --- | --- | --- |
| Personal baselines | `Packages/StrandAnalytics/Sources/StrandAnalytics/Baselines.swift`, `VitalBands.swift` | Reuse baseline states and expose numeric range boundaries alongside classifications. Vital banding currently requires 14 valid nights and a non-stale baseline for personal comparisons. |
| Vital presentation | `Strand/Screens/VitalSignsSummary.swift` | Extend current personal/population captions with explicit ranges and direction. |
| Metric details | `Strand/Screens/MetricExplorerView.swift`, `Strand/Data/MetricCatalog.swift` | Expand existing HRV/RHR baseline annotations into consistent context and explanations. |
| Profile | `Strand/Data/Profile.swift` | Use eligible, user-supplied age information for supported references; distinguish defaults from confirmed information. |
| Daily guidance | `ReadinessEngine.swift`, `TrainingLoadEngine.swift`, `SleepDebt.swift` | Reuse eligible evidence for explained, conservative suggestions. |
| Relationships | `BehaviorInsights.swift`, `CorrelationEngine.swift`, `Strand/Screens/InsightsView.swift` | Review evidence quality before promoting associations into recommendations. |
| Coach prompts | `CoachSuggestions.swift` | Audit units and thresholds before reuse; prompt chips are not a validated recommendation engine. |

Analytics filenames without a directory above refer to `Packages/StrandAnalytics/Sources/StrandAnalytics/`.

## First-release experience

### 1. Visible metric ranges

Show the value, units, comparison basis, numeric bounds where applicable, and a plain-language
state: below, within, or above the relevant range. For example:

> Resting HR: 68 bpm. Above your usual 54–62 bpm.

All example measurements in this plan are illustrative.

Keep three distinct concepts explicit: a personal usual range, a published population reference,
and a recommended target. A personal usual range does not establish health; a population
reference does not necessarily describe an individual's baseline.

| Metric | Primary context | Additional context |
| --- | --- | --- |
| Resting HR | Personal usual range | Applicable general adult reference, with measurement conditions explained |
| HRV | Personal range using comparable measurements | Age reference only when metric, recording method, duration, and population match |
| Respiratory rate | Personal range and change from baseline | Published reference only when applicable to the measurement context |
| Skin temperature | Personal change, with absolute and deviation values distinguished | No comparison of wrist temperature with a core-temperature fever threshold |
| Sleep duration | Age-appropriate published recommendation | Personal usual duration, labelled separately from the recommended target |
| Charge / Effort / Rest | NOOP score-band explanation and contributing factors | Personal trends; no invented age-based clinical reference |

Show a compact range bar and accessible text on supported cards, with fuller explanations in
metric details. Unsupported metrics retain a definition and trend rather than an invented range.
Keep raw, uncalibrated, unreliable, stale, or incompatible readings out of authoritative judgments.
Display learning or unavailable states with a specific reason and valid observation count.

### 2. Weekly comparisons

Compare the latest completed seven local calendar days with the preceding seven days. Label both
windows and coverage. Exclude today's partial day from this summary; handle historical views
using an explicit supplied anchor date.

Start with sleep duration and consistency, resting HR, HRV, and recorded training load. Use
comparable sources and methods, show absolute differences, and use percentages only when the
denominator is meaningful. Do not silently treat missing days as zero or compare partial totals
as though both weeks were complete. Define metric-specific coverage requirements before shipping.

### 3. At most three prioritised daily insights

Each insight contains an observation, an optional suggested action, and a short explanation.
Examples include a sustained departure from a personal range, a change in sleep patterns, or
recent training load compared with the user's longer-term pattern.

When reliable evidence supports it, a suggestion may say “Consider an easier day” and name
the contributing observations. Avoid disease diagnoses, injury predictions, or guarantees that
training is safe. Positive and neutral insights should be eligible too; an empty state is valid.
Training suggestions remain conditional on the rule's measurement compatibility and validation;
an existing readiness label alone does not establish either. If those conditions are unmet,
ship the descriptive comparison and withhold the action suggestion.

Rank by evidence quality, persistence, magnitude, and usefulness. Deduplicate related findings
so HRV, Charge, and readiness do not become three cards repeating the same underlying change.
Resolve conflicting signals into a qualified explanation instead of contradictory instructions.
Use deterministic, localised templates, independent of the optional AI Coach.

Tapping an insight shows its readings, source, reference window, sample counts, missing data,
and the rule that produced it. Quality labels describe data support, not a probability of health.

## Later increments

1. **Sleep planning:** suggest a bedtime window from intended wake time and an explicit sleep
   target; compare planned and recorded sleep. Do not automatically treat habitual short sleep
   as sufficient sleep or promise an exact recovery improvement.
2. **Behaviour comparisons:** compare explicitly logged presence and absence of behaviours with
   appropriate subsequent outcomes. Show group sizes, differences, uncertainty, and date windows.
   Use association language and allow the user to inspect the evidence.
3. **Comparable workouts:** compare sessions of similar activity, duration, and available context.
   Identify unmatched conditions; avoid interpreting a different route or effort as fitness change.
4. **Additional demographic references:** add only sourced references whose populations and
   measurement methods fit. Do not invent percentiles or peer rankings without suitable data.

These increments are outside the first-release acceptance criteria.

## Algorithm and data rules

- Use one canonical Swift context resolver for the displayed range, status, chart band,
  explanation, and accessibility label. Pass the anchor date and resolved evidence into views.
  Exclude the displayed observation and future observations from its personal reference history.
- Reuse the established baseline model initially. Preserve calibration and staleness handling;
  do not silently replace a personal range with a population range without naming the change.
  Treat the current statistical band as approximate, not a validated clinical confidence interval.
- Keep HRV methods such as SDNN and RMSSD separate. Respect source precedence, device changes,
  measurement duration, units, and skin-temperature semantics. Omit incompatible comparisons.
- Treat missing measurements as unknown, journal nonresponses as unanswered, and measured rest
  days as distinct from unobserved days. Respect baseline reset epochs and historical data edits.
- Do not present a score's relationship with its own inputs as an independent discovery.
  For example, HRV versus recovery can explain the recovery formula, but cannot establish that
  NOOP discovered a new physiological relationship.
- Before behaviour-based recommendations, define minimum coverage, meaningful effect sizes,
  uncertainty estimation, temporal alignment, repeated-observation handling, and a strategy for
  multiple comparisons. Check persistence in a later time window. Existing significance flags
  alone are insufficient justification for stronger claims.
- Distinguish a single unusual reading from a sustained change. Select persistence thresholds
  using varied fixtures and document them; repeated correlated signals are not independent proof.
- Version published references with source URL, supported population, measurement definition,
  units, applicability, and review date. Bundle the required reference data locally.
- Do not infer missing demographics or map an unsupported profile category to a reference group.
  Inspect profile default/confirmation semantics before enabling demographic labels.
- Compute on relevant data/profile changes and cache results. Avoid work on live-HR ticks or
  view redraws; invalidate caches when history, sources, reference versions, or profile inputs change.

## Implementation sequence

1. Audit existing thresholds, scale conversions, source compatibility, profile defaults, and
   overlapping range readers. Record which existing rules can be retained and which need review.
   In particular, review `ReadinessEngine`'s ACWR injury-risk framing and `CoachSuggestions`'s
   strain threshold against the current stored scale before exposing either through new guidance.
2. Add pure, structured metric-context results in Swift: value, reference basis,
   bounds or target, direction, observation date, evidence window, counts, and availability reason.
   Reuse existing storage where possible; any required migration must be additive. Avoid changes
   to shared backup contracts; any necessary contract change requires a separate scope review.
3. Add sourced age-based sleep guidance and consistent range presentation using design tokens,
   existing shared components, localisation, and accessible labels on iOS. Reusing these in a
   macOS UI is optional follow-up work.
4. Add weekly comparison results with explicit calendar and coverage rules.
5. Add deterministic insight selection and explanations, then integrate the three-card limit
   into Today with links to existing metric/detail screens.
6. Validate first-release behavior and performance before starting later increments. Keep each
   implementation PR focused and keep generated Xcode projects and build artifacts out of git.

## Validation and acceptance criteria

- [ ] Supported vitals display numeric context and clearly identify personal versus population
  references; sleep recommendations are labelled as targets, not observed normality.
- [ ] A card, its detail view, chart, and accessibility text agree for the same observation.
- [ ] Calibration, stale history, missing data, unverified readings, source changes, and baseline
  resets have explicit behavior; no plausible-looking fallback hides an unavailable comparison.
- [ ] Weekly windows, coverage, units, and comparisons agree across iOS screens, including
  timezone/daylight-saving boundaries and incomplete weeks.
- [ ] Today shows zero to three nonredundant insights with inspectable evidence and no circular
  discoveries, conflicting prescriptions, or unsupported medical/peer-ranking claims.
- [ ] Each shipped comparison or recommendation has an evidence record identifying its source,
  applicability, algorithm version, implementation choices, and remaining validation limits.
- [ ] Pure tests cover boundaries, varying inputs, demographic eligibility, historical anchors,
  incompatible HRV methods, absolute/deviation temperature, and unchanged scoring outputs.
- [ ] Swift fixtures pin numeric and decision boundaries and prevent later drift. Review
  translated wording and formatting separately from numerical correctness.
- [ ] Run relevant Swift package tests and build `NOOPiOS`. Build `Strand` for compatibility when
  shared app-target files change, and run relevant `StrandTests`; package CI alone does not
  compile the Apple apps. Run applicable source-hygiene and translation checks.
- [ ] Review iOS layouts, accessibility, and design-token use. Measure computation
  frequency and device performance; report battery evidence separately from build/test success.

## Expected impact

This is a moderate iOS feature, building on existing Swift analytics while adding a shared
interpretation layer and consistent iOS UI. macOS adoption is optional. Reference selection and evidence quality require more
care than simply drawing ranges. No schema change is assumed until the implementation audit.

Processing existing data on change should add little overhead, but battery impact remains
unmeasured. No extra BLE sampling or network service is required. The main product risk is
misleading certainty; explicit reference types, data-quality gates, and inspectable explanations
are part of the feature, not optional disclaimer text.

## Research assessment for comparisons and recommendations

Reviewed on 2026-09-22. This is a focused literature assessment, not a systematic review or
clinical validation. Sources include original studies, official consensus/guidance, and explicitly
identified methodological reviews. Some findings were assessed from published abstracts; those
are identified below and require full-method review before any protocol is implemented.

### Comparisons: evidence and resulting product decisions

| Comparison | Research finding and scope | Proposed NOOP decision |
| --- | --- | --- |
| Personal resting-HR range | Quer et al. (2020) studied 92,457 wearable users longitudinally. RHR differed substantially between people while generally varying less within a person. The device used a proprietary calculation and the cohort was not fully representative. [Original study](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0227709). | Prioritise personal history. The study supports this design direction, not NOOP's specific baseline estimator, 14-night gate, or medical alarm threshold. |
| Age-related HRV | Voss et al. (2015) analysed five-minute ECG recordings from 1,906 healthy participants aged 25–74 and found age- and sex-related differences in HRV indices. [Original study](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0118308). | Demographic comparisons are plausible, but these tables cannot simply classify overnight wearable HRV. Require matching metric and measurement protocol; otherwise show personal context only. Do not extrapolate outside the studied ages. |
| HRV measurement compatibility | Shaffer and Ginsberg (2017), a review of HRV metrics and norms, explains why recording duration and measurement context affect interpretation. [Review](https://www.frontiersin.org/journals/public-health/articles/10.3389/fpubh.2017.00258/full). | Keep SDNN and RMSSD separate and preserve source/protocol metadata. A shared unit of milliseconds does not make readings interchangeable. |
| General resting-HR reference | American Heart Association guidance describes 60–100 bpm for most calm, resting adults, with individual variation including athletic conditioning. [Official guidance](https://www.heart.org/en/health-topics/high-blood-pressure/the-facts-about-high-blood-pressure/all-about-heart-rate-pulse). | Use only as labelled general context with its conditions. Do not use it as an age-specific chart or apply an awake resting reference as an automatic judgment of sleeping HR. |
| Sleep duration versus age | The AASM/SRS adult consensus recommends regularly sleeping at least seven hours; CDC presents recommendations for different age groups. [Consensus statement](https://pmc.ncbi.nlm.nih.gov/articles/PMC4442216/), [CDC table](https://www.cdc.gov/sleep/about/). | Bundle sourced, age-appropriate targets. Preserve one-sided recommendations such as “at least” instead of inventing an upper normal limit. Keep targets distinct from habitual sleep duration. |
| Sleep regularity and weekly trends | Phillips et al. (2017) followed 61 undergraduates for 30 days and linked irregular sleep with later circadian timing and poorer academic performance. This was observational and population-specific. [Original study](https://doi.org/10.1038/s41598-017-03171-4). | Show sleep timing consistency as a descriptive trend. Do not promise a performance improvement. A bedtime-spread measure must not be labelled the study's Sleep Regularity Index, which uses sleep/wake states across days. |
| Reliability of wearable inputs | Miller et al. (2022) assessed six devices against laboratory references in 53 adults over one night, including WHOOP 3.0. A later nocturnal study included WHOOP 4.0, with 13 adults and 536 recorded nights. [2022 original study](https://www.mdpi.com/1424-8220/22/16/6317), [later study, abstract assessed](https://pubmed.ncbi.nlm.nih.gov/40834291/). | Treat device, protocol, and processing pipeline as part of applicability. Neither study validates NOOP's independent decoding or analytics, and many nights from a small group do not establish population-wide accuracy. |

No suitable directly transferable reference table was established in this review for NOOP's
respiratory-rate or wrist-temperature pipelines. Personal comparisons may use reliable compatible
history; new population classifications for these measurements require a separate source and
applicability review. Comparable-workout analysis also remains a descriptive later increment,
without a claim that it measures changes in fitness or predicts performance.

### Algorithmic recommendations: evidence and resulting product decisions

| Recommendation | Research finding and scope | Proposed NOOP decision |
| --- | --- | --- |
| Adapt training to personal recovery evidence | Kiviniemi et al. (2007) randomised 26 moderately fit men into training/control groups over four weeks. Vesterinen et al. (2016) studied 40 recreational endurance runners; morning-HRV-guided training used fewer moderate/high-intensity sessions, with a small between-group difference in running-performance change. [2007 study](https://pubmed.ncbi.nlm.nih.gov/17849143/), [2016 study](https://pubmed.ncbi.nlm.nih.gov/26909534/). These summaries are based on abstracts. | Evidence supports investigating individualised training timing. It does not validate copying a threshold into NOOP's overnight HRV/Charge pipeline or generalising to every activity and user. Start with qualified suggestions only when measurement compatibility and rule validation are established; never promise injury prevention. |
| Review recent training load | Impellizzeri et al. (2020) identifies conceptual and statistical problems in using acute:chronic workload ratios as causal injury-risk predictors. [Methodological analysis, abstract assessed](https://pubmed.ncbi.nlm.nih.gov/32502973/). | Show recent and longer-term load descriptively. Do not turn a ratio “sweet spot” into a safe-training zone or injury-risk percentage. This restriction applies even if existing NOOP comments or labels imply stronger evidence. |
| Plan sleep opportunity | The AASM/SRS consensus supports a population sleep-duration recommendation, while CDC also encourages consistent bed/wake schedules. [Consensus statement](https://pmc.ncbi.nlm.nih.gov/articles/PMC4442216/), [CDC guidance](https://www.cdc.gov/sleep/about/). | A bedtime window can be calculated from intended wake time and an explicit target. Any allowance for usual sleep latency is a transparent product estimate. Do not imply that time in bed equals sleep or that an exact sleep-debt repayment formula is clinically established. |
| Learn from logged behaviours | CENT guidance describes prospective, repeated crossover N-of-1 trials and transparent reporting. Ordinary behaviour logs lack those controls. [CENT explanation and elaboration](https://doi.org/10.1136/bmj.h1793). The accessible summary was assessed; detailed methods remain to be reviewed. | Observational comparisons may surface a tentative association, not a causal prescription. Treat missing responses distinctly, align behaviours with subsequent outcomes, and account for competing explanations before suggesting a pattern is actionable. This does not add clinical self-experimentation to the scope. |

### Proposed algorithms and what remains to validate

The following are engineering proposals informed by the evidence above. They are not published
clinical rules, and thresholds must not be attributed to the papers unless reproduced faithfully.

1. **Personal context:** extend the existing resolver to return its center and effective bounds.
   For the current trusted vital band, its nominal bounds follow the existing rule
   `baseline ± sigmaK × 1.253 × spread`, subject to existing plausibility guards. Test exact
   agreement with the status resolver before displaying those bounds. Do not describe this
   approximate model as a guaranteed 95% reference interval.
2. **Week-over-week changes:** calculate the difference between comparable summaries of two
   completed weeks. Include observation counts and data completeness. Seven-day windows are a
   product convention, not a research-derived diagnostic threshold. Summarise bedtime/wake time
   with midnight-aware arithmetic; never average 23:55 and 00:05 into a noon bedtime.
3. **Persistent departures:** evaluate past-only personal deviations across calendar days and
   require persistence before promoting a trend to a daily insight. Quer et al. used a specific
   research definition involving prior measurements and repeated elevations; NOOP must validate
   its own rule rather than treat that definition as a clinical alarm. Test isolated artifacts,
   gradual changes, recovery to baseline, and wear gaps.
4. **Daily suggestion selection:** create structured evidence first, then apply compatibility and
   quality gates, then select at most three distinct insights. A recommendation's eligibility must
   be tested separately from whether its template is grammatically correct. Suppress the action
   if only an unsupported inference remains; retain the useful observation.
5. **Behaviour associations, later:** predefine candidate behaviour/outcome pairs and temporal
   lags. Compare explicitly answered groups with sufficient independent information, report effect
   sizes and uncertainty, and check later-window stability. Evaluate a multiple-testing correction
   and a method that respects serial dependence. Test null data, autocorrelation, confounding,
   unequal groups, missing responses, and injected effects before choosing release thresholds.

Calibration uses recorded or synthetic fixtures without changing live scoring. Synthetic tests
can establish mathematical behavior and false-positive behavior under stated assumptions; they
cannot establish medical validity or real-world benefit. Retrospective checks must use only data
available at each historical decision and preserve a later evaluation period.

For each rule, document which thresholds come from existing NOOP behavior, which come from a
compatible publication, and which are new product choices. Freeze acceptance criteria before
evaluating the final held-out cases. A first release can deliver ranges and comparisons while
withholding recommendations that have not met these requirements.

## Apple Intelligence assessment: iPhone 15 Pro

Decision, 2026-09-22: **evaluate Apple's on-device Foundation Models for optional explanations
and journal entry assistance after the deterministic comparison layer is working.** Keep the
range calculations, evidence selection, recommendation eligibility, and scores in Swift. This
assessment adds a bounded evaluation phase, not a requirement to ship generative AI.

### Available capabilities and constraints

- The iPhone 15 Pro supports Apple Intelligence. The app-facing `SystemLanguageModel` API is
  available from iOS 26; availability must be checked at runtime.
  Keep NOOP's iOS 17 deployment target and availability-gate the optional feature. Device
  eligibility alone does not establish that the model is installed, enabled, or ready.
  [Apple device requirements](https://support.apple.com/en-us/121115),
  [model availability](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel).
- Current iOS 27 documentation describes updated on-device models. Apple's AFM 3 Core is its
  roughly three-billion-parameter model; Core Advanced requires newer hardware and is not an
  iPhone 15 Pro capability. Design and benchmark for the smaller model. Do not extrapolate
  latency or quality from a newer iPhone or Mac.
  [Apple model research](https://machinelearning.apple.com/research/introducing-third-generation-of-apple-foundation-models),
  [hardware restrictions, footnote 1](https://www.apple.com/newsroom/2026/06/apple-introduces-siri-ai-a-profoundly-more-capable-and-personal-assistant/).
- `SystemLanguageModel` works offline once ready. Apple currently documents a 4K context for
  its on-device option versus 32K for Private Cloud Compute. Query supported capacity where
  available and budget instructions, tool definitions, input, and output together. Send concise
  resolved evidence, not a raw database or months of sensor samples.
  [Apple model comparison](https://developer.apple.com/documentation/FoundationModels/adding-server-side-intelligence-with-private-cloud-compute/).
- The framework supports structured output with `@Generable`, extraction, summarisation, and
  calling app-defined tools. Structured output constrains shape, not factual accuracy.
  [Foundation Models overview](https://developer.apple.com/documentation/foundationmodels),
  [tool calling](https://developer.apple.com/documentation/foundationmodels/tool).
- Verify language support at runtime. Apple's current system support includes English and Dutch,
  with feature and regional differences; that is not proof every requested model/locale is ready.
  System assets require storage and may need an initial download. The current support page lists
  up to 8 GB for this class of device, shared system assets rather than a NOOP app download.
  [System requirements](https://support.apple.com/en-us/121115).
- Siri features and models available directly to an app are different surfaces. Do not make
  this feature depend on Siri AI availability or assume all Apple Intelligence runs offline.
  Explicitly select `SystemLanguageModel`; Private Cloud Compute and third-party providers are
  outside this feature's scope. No automatic network fallback.

### Which uses are worth pursuing

| Use | Decision | Reason and boundary |
| --- | --- | --- |
| Explain a metric or weekly summary | First prototype | Generate a short explanation from facts and references already selected by Swift. Keep authoritative numbers and range labels rendered directly from structured data. |
| Turn journal prose into structured entries | Second prototype | Extract explicit behaviours and dates into a reviewable draft, including negation and uncertainty. “No alcohol, late dinner” must not log alcohol. Save only after the user reviews it. |
| Ask questions about personal trends | Later, if explanation quality is useful | Map a question to allowlisted, read-only comparison functions. Swift computes the answer; the model explains it. No generated SQL, arbitrary tool access, or writes to health data. |
| Reuse on-device voice input | Reuse existing implementation | `StrandiOS/App/CoachVoiceInput.swift` already requests local speech recognition and gates unsupported locales. A new speech model is not required for the initial feature. |
| Siri / App Intents integration | Optional later convenience | Useful for opening a metric or initiating a journal draft, but not necessary for the in-app comparison/recommendation experience. |
| Calculate health ranges, scores, or choose training prescriptions | Do not use a language model | Reproducible Swift calculations and explicit evidence gates remain the authority. Model output must not create thresholds or alter recommendations. |
| Image generation, screenshot analysis, or a custom downloaded model | Defer | No demonstrated benefit for this scope; existing structured data is a better input than a screenshot. Custom models add packaging, performance, and maintenance work before value is established. |

Apple specifically describes on-device Foundation Models as suitable for personalising content
in health and fitness apps. This supports evaluating explanations, not claiming that the model
has clinical reasoning validity. Health-related requests can encounter guardrails; preserve
refusals and use the deterministic explanation rather than attempting to bypass them.
[Apple health and fitness guidance](https://developer.apple.com/health-fitness/),
[model safety guidance](https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output),
[acceptable-use requirements](https://developer.apple.com/support/terms/acceptable-use-requirements-for-the-foundation-models-framework).

### Integration and evaluation plan

1. Add a small iOS service around `SystemLanguageModel` and `LanguageModelSession`, isolated from
   pure analytics and availability-gated. A dedicated explanation service is preferable initially
   to routing through the current Coach provider protocol, which expects API keys, model-list
   requests, and a `URLSession`. Repository inspection found no existing Foundation Models adapter.
2. Supply a compact evidence bundle containing metric IDs, dates, sources, verified values,
   comparison basis, selected finding IDs, allowed wording, and limitations. Research links come
   from the curated registry, never model memory. Preserve numeric cards as the authoritative UI.
3. Request structured output containing a short explanation and references to supplied evidence
   IDs. Reject unknown IDs, altered numbers/units/dates, unsupported causation, diagnoses, or
   new advice. Schema validation alone cannot guarantee semantic faithfulness; use curated
   evaluation and deterministic fallbacks, and withhold the feature if acceptable reliability
   cannot be achieved. Never stream unvalidated health claims straight into the final UI.
4. Make generation optional and user-initiated, such as an “Explain” action. Generate in the
   foreground, cancel when no longer needed, and cache by evidence, locale, prompt/rule version,
   and available model identity. Do not run during strap sync, on live-HR ticks, or as an overnight
   background task. Existing template explanations remain immediately available.
5. Run representative cases on a physical iPhone 15 Pro: ordinary and contradictory readings,
   insufficient history, stale data, source changes, English/Dutch where available, negated
   journal entries, malformed input, and requests outside the allowed scope. Treat user notes
   as data, not instructions capable of overriding tools or access boundaries.
6. Compare the generated explanations with templates for usefulness and faithfulness. Record
   latency, peak memory, thermal behavior, energy, refusal/fallback frequency, and extraction
   precision. Verify offline operation with the model already downloaded, plus graceful behavior
   when Apple Intelligence is disabled, unavailable, or still downloading. Do not log personal
   prompts or responses to telemetry.
7. Check cancellation, cache invalidation, default-off behavior, and no network fallback. No
   numerical or decision output may change when the AI option is toggled. Choose explicit
   performance/quality acceptance thresholds before evaluating held-out cases. Re-evaluate after
   OS/model updates because Apple changes the underlying model.
   [Apple framework updates](https://developer.apple.com/documentation/updates/foundationmodels).

The first prototype should be a short “Explain this comparison” action, not an unrestricted
health chatbot. Promote it only if it is more useful than the existing template at acceptable
latency and energy cost. macOS reuse remains optional, and no Android implementation is planned.

Verification boundary: runtime model readiness, inference quality and energy cost require physical-device evaluation.

## Expanded evidence and activity implementation

The iOS expansion now covers all 34 WHOOP/NOOP catalog metrics and the 12 Apple
Health, nutrition and mood entries. It adds source-aware descriptive comparisons,
walking feedback, recorded strength days, an explicit aerobic-minute review,
conditional movement breaks and sleep-timing feedback. Research applicability,
algorithm gates and known limits are recorded in [METRIC_EVIDENCE.md](METRIC_EVIDENCE.md).
Android implementation remains outside this feature scope.
