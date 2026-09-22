# Metric evidence and activity guidance audit

Research review: 2026-09-22. Scope: iOS, with shared Apple code compatible with macOS. Android
implementation is outside this feature scope. No stored physiological
formula, schema, BLE command, sync schedule or Android implementation changes here.

## What is counted

`MetricCatalog.all` has **60 source-specific entries**, not 27 directly sensed
quantities: **34 WHOOP/NOOP**, **7 Apple Health**, **4 nutrition**, **1 mood**, and
14 separate Mi Band imports. The new iOS evidence browser covers the first **46**;
the classifier also recognizes all Mi Band keys, without claiming WHOOP validation
for Mi Band. HealthKit separately requests **16 quantity read types**, plus sleep,
workout and route types. Quantities, catalog entries and computed outputs are
different counts. Availability depends on the user's records and permissions.

WHOOP 4 hardware validation does not validate NOOP's clean-room processing or
automatically apply to WHOOP 5/MG. No universal “accuracy percentage” is assigned
to a metric. The UI links relevant research or guidance, and explicitly describes
where there is no applicable validation. Demographic formula fixtures are not
clinical validation in males aged 20–40 or heights 160–200 cm.

## Research reviewed

| Reference | Actual evidence and applicability |
|---|---|
| [Dial et al., 2025](https://physoc.onlinelibrary.wiley.com/doi/10.14814/phy2.70527) | 13 adults, 536 total study nights across devices; WHOOP 4 HRV had 289 paired nights. Reported WHOOP RHR MAPE 3.00 ± 2.15%, HRV MAPE 8.17 ± 10.49%. These are study-level errors, not individual confidence intervals or guaranteed accuracy. The tested nocturnal WHOOP processing differs from NOOP. |
| [Rehman et al., 2024](https://doi.org/10.3390/s24216826) | WHOOP 4 and Corsano PPG compared with an ECG patch in 25 healthy adults over two five-day periods. HRV error depended on activity, usable signal and epoch length. Intensive exercise was excluded. This supports distinguishing overnight/resting from active measurements; it does not validate NOOP's R–R pipeline. |
| [Schyvens et al., 2025](https://academic.oup.com/sleepadvances/article/6/2/zpaf021/8090472) | 62 adults, mean age 46, including suspected sleep-apnea patients; one PSG night per person. WHOOP 4 subset n=40. Table 7 reports kappa 0.37, sleep sensitivity 93.58% and wake specificity 40.13%. Deep and REM totals were overestimated on average, with wide individual disagreement. Do not mislabel this as a healthy 20–40-only sample or apply its accuracy to NOOP. |
| [WHO adult physical activity guideline, 2020](https://www.who.int/publications/i/item/9789240015128) | 150–300 moderate or 75–150 vigorous aerobic minutes/week, or an equivalent mix; strengthening all major muscle groups on at least two days. Some activity is better than none; increase gradually and reduce sedentary time. Neither an exact movement-break timer nor NOOP Effort/HR-zone conversion follows from this guideline. |
| [CDC intensity guidance](https://www.cdc.gov/physical-activity-basics/measuring/index.html) | Talk test supports self-reported intensity: moderate allows conversation but not singing; vigorous allows only a few words before a breath. Existing workout records lack reliable intensity metadata, so the new review uses explicitly entered minutes. |
| [Ding et al., 2025](https://pubmed.ncbi.nlm.nih.gov/40713949/) | Prospective-study meta-analysis links greater recorded steps with health outcomes. Observational associations, residual confounding and lack of age-specific analysis prohibit causal personal risk predictions or a universal 7,000/10,000 prescription. It does not validate NOOP's WHOOP 4 motion-to-step conversion. |
| [CDC sleep guidance](https://www.cdc.gov/sleep/about/) | Age-based sleep duration and consistent sleep/wake schedules. Bedtime circular standard deviation is descriptive; it is not the Sleep Regularity Index. A 15-minute reduction used for feedback is a product filter, not a clinical threshold. |
| [Uth et al., 2004](https://pubmed.ncbi.nlm.nih.gov/14624296/) | Heart-rate-ratio VO₂max work in 46 trained men, ages 21–51. It is neither WHOOP validation nor validation of NOOP's complete fitness/body-age model; replacing measured maximal HR with an age estimate adds uncertainty. |
| [Keytel et al., 2005](https://pubmed.ncbi.nlm.nih.gov/15966347/) | Exercise energy-expenditure equations, with population and exercise-condition limits. Reproducing coefficients does not make daily calorie burn, low-intensity extrapolation or a food allowance accurate. See the existing research regression tests for equation fixtures. |
| [Frija-Masson et al., 2021](https://pubmed.ncbi.nlm.nih.gov/33929337/) | Smart-scale weight and body-composition validation distinguishes weighing from bioimpedance estimates; results are device-specific and do not validate every Apple Health source. |
| [CDC BMI FAQ](https://www.cdc.gov/bmi/faq/) | BMI is a screening measure, not a direct body-fat measurement or personal ideal-weight prescription. |
| [FDA pulse oximetry limitations](https://www.fda.gov/medical-devices/products-and-medical-procedures/pulse-oximeters) | Context for imported oxygen measurements and device-dependent error. Not validation of uncalibrated NOOP raw fields or a justification for applying clinical thresholds to them. |

No applicable independent validation was established in this review for NOOP's
skin-temperature conversion, raw oxygen/respiration fields, calibrated motion-step
estimate, composite scores, stress, sleep-need/debt calculation or biological-age
interpretations. “Trends only” is a restriction on interpretation, not a claim that
the trend itself has been validated. Imports retain their originating method's limits.

## Catalog coverage

The grouping below exhausts the 34 WHOOP/NOOP entries. A group shares an explanation
only when the same interpretation limit applies; each entry remains individually
accessible in the iOS catalog and its metric detail screen.

| Metric keys | Interpretation |
|---|---|
| `avg_hr`, `max_hr`, `rhr` | Optical estimates; resting/overnight evidence is stronger than arbitrary peaks under movement. RHR retains the existing quality-aware personal-range path. |
| `hrv` | Same-source/method trends only; RMSSD and SDNN are kept separate, R–R over-count flags withheld. |
| `resp_rate`, `spo2` | Raw WHOOP 4 fields uncalibrated; no generic comparison, normal-value band or health advice. Imported values retain their source limits. |
| `skin_temp` | Provisional conversion, trend interpretation only; absolute skin temperature and baseline deviations must not be mixed. Existing context handles eligible absolute observations. |
| `sleep_total_min`, `in_bed_min`, `sleep_efficiency` | Sleep estimates, sensitive to quiet wakefulness and sparse motion. Sleep-duration advice retains existing source/quality gates. |
| `sleep_deep_min`, `sleep_rem_min`, `sleep_light_min`, `restorative_min`, `restorative_pct` | Uncertain stage-derived trends, no stage targets or diagnostic advice. |
| `sleep_need_min`, `sleep_debt_min`, `hours_vs_needed_pct`, `sleep_consistency` | Descriptive model estimates; no precisely measured sleep deficit or biological requirement. |
| `energy_kcal` | Estimated energy trend, no precise calorie deficit or food allowance. |
| `recovery`, `strain`, `sleep_performance`, `vitality`, `stress` | Algorithm scores, no clinically established normal range, illness diagnosis, psychological diagnosis or safe-load prescription. |
| `fitness_age`, `body_age`, `vo2max_est` | Model estimates; no generic comparison that could join different fitness estimators. |
| `steps` | Imported/WHOOP 5 count estimates; not a measured WHOOP 4 BLE step stream. |
| `steps_est` | WHOOP 4 motion estimate, sensitive to calibration and arm motion; descriptive only, excluded from walking prescriptions. |
| `hr_zones13_min`, `hr_zones45_min`, `hr_zones_all_min`, `strength_min` | Recorded activity categories; no automatic conversion to guideline intensity or muscle-group coverage. |

The remaining 12 in-scope entries are Apple Health `vo2max`, `steps`, `active_kcal`,
`weight`, `body_fat`, `lean_mass`, `bmi`; nutrition `calories_in`, `protein_g`,
`carbs_g`, `fat_g`; and personal `mood`. None is presented as directly measured by
WHOOP. Food logs and mood entries receive interpretation limits, not fabricated
WHOOP accuracy numbers, clinical cutoffs or dietary prescriptions.

## Algorithms and safeguards

- All additional catalog comparisons use two **completed** seven-day windows,
  excluding the selected anchor day. Each daily average needs five distinct valid
  days per week. Missing days are absent, never filled with zero; conflicting
  duplicates, negative/non-finite/out-of-representable-range inputs are excluded.
  One storage namespace and metric key must cover the comparison. A failed store
  read withholds the window. These are descriptive averages, not weekly totals.
- RHR, HRV, sleep duration, respiration and skin temperature retain the original
  quality-aware context route. Oxygen and estimator-sensitive fitness/body-age
  values do not get a generic comparison that could bypass those gates.
- Apple Health steps drive walking feedback when both weeks have coverage.
  A drop beyond 10% selects conditional “consider a manageable extra walk” text;
  this is a product noise filter, not a clinical cutoff. Stable/higher records get
  maintenance feedback. No step target or risk-reduction percentage is prescribed.
  The Apple Health aggregate does not prove the original physical device, consistent
  phone carriage or full-day wear. The UI says Apple Health, not measured phone steps.
- WHOOP 4 estimated steps remain viewable with calibration caveats, but are never
  used to prescribe a precise walking target. Historical calibration version is
  not stored, so changes may reflect calibration rather than physiology.
- Strength counts distinct local start days with completed, explicitly labelled
  strength sessions (including lifting imports). Detected bouts, future sessions,
  duplicate sessions on the same day and ambiguous sport labels cannot inflate
  the day count. Fewer than two recorded days produces conditional planning advice,
  never an inactivity diagnosis. Two days is not proof all major muscles were trained.
- The aerobic review stores the user's two minute totals locally, separately for
  each explicit seven-day date window. Empty is unknown; zero is an explicit entry.
  Equivalent moderate minutes = moderate + 2 × vigorous. Adult guidance requires
  confirmed age 18–120. Inputs must be finite, non-negative and sum to at most
  10,080 actual minutes. No HR-zone, sport-name, Effort or calorie shortcut supplies
  intensity. The review currently needs separate entry for each sliding date window.
- Bedtime feedback uses the existing quality-gated circular comparison across
  midnight, and never equates it with the clinical Sleep Regularity Index. Positive
  feedback describes recorded regularity, not improved health. Movement-break
  guidance is conditional on the person having sat; no stillness-to-sitting inference,
  timer, notification, new background task or increased strap polling is introduced.
- Apple Intelligence continues to select only approved statement IDs. The main
  explanation now includes deterministic insight and weekly-comparison facts;
  activity has a separate bounded explanation, and expanded comparable metrics
  can explain their own evidence and two weekly averages. Generation is opt-in,
  on demand and cancelled on dismissal/background/data change. No generated
  diagnosis, new target, source attribution or advice can enter the UI.

## Validation and device testing

`ActivityGuidanceTests` covers guideline equivalence across ages 20–40,
unknown/child ages, incomplete versus explicit-zero
input, date windows, source changes, duplicates, missing days, invalid numbers,
step feedback and distinct strength days. `MetricEvidenceCatalogTests` covers
every current catalog key and the 34/46 in-scope counts. Existing research and
adapter fixtures continue to cover source semantics and WHOOP 4 quality limits.
The existing formula regression fixtures cover male profiles aged 20–40 and
160–200 cm. Height is not an input to the adult activity guideline and no
height-specific activity accuracy is claimed.

Package tests and app compilation do not
establish sensor accuracy, physical-device layout or Apple Intelligence runtime
availability. On an iPhone, check long localized evidence text, expansion of each
category, missing Health permissions, age confirmation, week changes, entry
persistence, keyboard dismissal and cancellation of on-device explanations.
