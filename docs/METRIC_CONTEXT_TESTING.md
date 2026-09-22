# Metric context: verification guide

Scope: iOS, with shared-source macOS compatibility. Android implementation is outside this feature.
See [METRIC_EVIDENCE.md](METRIC_EVIDENCE.md) for catalog-wide evidence and activity guidance.

## Implemented

- Today, in both layouts, and Health expose **Your ranges & insights**. Health uses this context
  surface instead of its older vitals grid, avoiding a second population-based range verdict.
- Detail sheets show source/method, measurement date, applicable numeric range, reference period,
  valid-night count, research links and two completed weeks with coverage. Units follow preferences.
- RHR, HRV, eligible respiration and absolute wrist-temperature histories use the existing robust
  baseline/deviation calculation, with 14 trusted prior nights. No cold-start age-based HRV range
  is invented. Missing dates affect staleness; the displayed observation cannot enter its reference.
- Sleep guidance uses a confirmed date of birth and the age at the viewed date. Adults 18–60 have
  a minimum of seven hours, without an invented upper limit. Height and sex do not modify this
  recommendation. The profile's automatically supplied default age requires explicit confirmation.
- Weekly means require at least five eligible days in each week; recorded effort-score sums require
  seven. Today is excluded. Bedtime variation is circular standard deviation in minutes, not SRI.
- At most three deterministic insights: descriptive sustained deviations, weekly changes, and a
  sleep-opportunity suggestion only after three consecutive eligible nights below the minimum.
  The persistence/coverage rules are product choices, not published diagnostic cutoffs.
- Source switches, unknown provenance, nonfinite/implausible values, HRV overcount flags, sparse
  sleep and baseline resets withhold inappropriate comparisons or suggestions. Reads retain
  per-field storage namespaces before the repository's ordinary merge discards them.
- Optional Apple Intelligence preview selects up to three IDs from existing approved explanation
  statements. Output IDs must be distinct and allowlisted; the displayed text is copied from those
  statements, never generated health prose. No network/provider fallback. Backgrounding, dismissal,
  opt-out and data changes cancel presentation. Unavailable models/languages use standard text.
- New interface text is translated into de, es, fr, pt-PT, it, pl, ru, zh-Hans and zh-Hant.

## WHOOP 4 interpretation

These restrictions apply to NOOP's independently decoded/computed values. A validation of the
official WHOOP app is not validation of NOOP's parser, sleep stager or calorie algorithm. Imported
WHOOP and Apple Health data retain their source and method; Apple SDNN is not mixed with RMSSD.

| Measurement | Label / interpretation in the new surface |
| --- | --- |
| Resting heart rate | Optical estimate in bpm; personal comparisons, not an ECG or diagnosis. Motion and fit matter. |
| HRV | Personal trends using the same source/method. Known R–R overcount is excluded. No age percentile or comparison with five-minute ECG norms. |
| Skin temperature | Provisional conversion; trends only. Wrist temperature is not core temperature or a fever threshold. |
| Sleep duration / stages | Algorithm estimates; patterns rather than precise clinical totals. NOOP-computed sleep does not trigger the absolute-duration recommendation. Sparse/HR-only sleep is excluded from comparisons. |
| Calories, effort, recovery | Model/score trends. No calorie prescription, safe-load zone or injury prediction. |
| Fitness/body age and VO₂max | Model estimates; not a measured biological age or laboratory fitness test. |
| Steps / distance | Motion estimates; trends rather than exact counts or distances. |
| Raw red/IR oxygen and respiration-adjacent fields | Uncalibrated: not SpO₂ percentages or breaths/minute. No health range/advice; unverified context readings show no physiological numeric value. |

Hardware basis: [`PROTOCOL_SENSORS.md`](PROTOCOL_SENSORS.md), WHOOP 4 historical v24 table, and the
documented sparse-motion staging limitations. Absolute offsets backed by captures do not establish
clinical accuracy. The [2025 nocturnal WHOOP 4 study](https://pubmed.ncbi.nlm.nih.gov/40834291/) is
relevant background for optical estimates, but its official-device workflow does not validate NOOP.

## Research and regression checks

| Reference | Check and limit |
| --- | --- |
| [AASM/SRS adult sleep consensus](https://pmc.ncbi.nlm.nih.gov/articles/PMC4442216/) and [CDC age guidance](https://www.cdc.gov/sleep/about/) | Every integer age 20–40 × height 160–200 cm (861 male profiles) retains the adult minimum of 420 minutes, without an upper ceiling. Adjacent age categories and unknown age are tested. This is recommendation applicability, not individualized sleep-need validation. |
| [Quer et al., 2020](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0227709) | Supports within-person RHR interpretation. Tests pin the incumbent baseline's boundary behavior, historical exclusion, gaps and resets; the paper does not validate NOOP's exact range algorithm. |
| [Voss et al., 2015](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0118308) | Short resting ECG measurements and a cohort starting at age 25 do not justify overnight wearable age norms, especially at age 20. Tests require learning/unavailable instead of inventing a demographic HRV range. |
| [Roza & Shizgal, 1984, Table 3 equation 3](https://zakboekdietetiek.nl/wp-content/uploads/2015/06/roza-1984.pdf) | Existing male resting-energy coefficients match the paper. Independent fixtures span 20/160, 30/180 and 40/200; the full 861-point grid checks centimetre/metre and day/second conversion. The paper's rounded 70 kg, 170 cm, age 50 example is reproduced. This is resting energy, not measured daily expenditure. |
| [Tanaka et al., 2001](https://pubmed.ncbi.nlm.nih.gov/11153730/) | Existing population HRmax equation reproduces 194, 190.5, 187, 183.5 and 180 bpm at ages 20, 25, 30, 35 and 40. It is not a measured personal maximum or a reason to force training intensity. |
| [Keytel et al., 2005](https://pubmed.ncbi.nlm.nih.gov/15966347/) ([author-uploaded full text](https://www.researchgate.net/publication/7777759_Prediction_of_energy_expenditure_from_heart_rate_monitoring_during_submaximal_exercise)) | Base male exercise-energy coefficients and kJ/min→kcal/s conversion match independent fixtures. Existing three-decimal fitness-adjusted slopes remain within 0.03 kcal/min of the four-decimal published table for the three tested profiles. The study used exercising adults and measured VO₂max; feeding an HR-derived VO₂max or applying the equation all day is not validated by coefficient agreement. No scoring coefficients were retuned. |

Pure checks additionally cover midnight/DST day windows, circular bedtime values, absent days versus
zero effort, incompatible SDNN/RMSSD, source switches, NaN/infinity, reset boundaries and duplicate
card suppression. App integration checks cover source priority, namespaces, WHOOP 4 classification,
temperature semantics, HR-only sleep, overcount and unknown provenance.

## Reproducible validation

Run `swift test --package-path Packages/StrandAnalytics`, the metric adapter/catalog app tests,
`Tools/doc_comment_lint.py`, and `Tools/i18n_audit.py --ci <base-ref>`. Generate the Xcode project
and compile both NOOPiOS and Strand when shared app source changes. Use the `NOOP_TEST_HOST`
compilation flag for a minimal macOS test host that does not initialize BLE.
App and widget versions, App Groups, signatures and ZIP integrity must agree when packaging.
Keep build manifests, installation records and local artifact paths outside tracked documentation.

On an iPhone 15 Pro:

1. Open both Today layouts and Health. Expand ranges and weekly comparisons; verify light/dark,
   large Dynamic Type and VoiceOver. Confirm no range labels are clipped.
2. With WHOOP 4 selected, verify the visible trend warning and full hardware guide. Confirm raw
   respiration has no physiological number/range, flagged HRV is withheld, and computed sleep does
   not produce an absolute sleep-deficit recommendation.
3. Confirm date of birth, revisit a historical date and change the profile. Check age guidance and
   temperature units. Missing or unconfirmed age must not silently become age 30.
4. Switch source/device and HRV settings; reset baselines. Incompatible histories must become
   learning/unavailable rather than inheriting the previous range or weekly comparison.
5. Verify the two week dates and coverage against recorded days. Try missing days, no history,
   imported WHOOP, Apple SDNN and a mixed-source fortnight.
6. On iOS 26+, enable the optional local explanation with Apple Intelligence ready. Check offline
   operation, language availability, model-not-ready/off behavior, interruption and cancellation.
   Numbers and recommendations must stay identical with the toggle on or off. Measure response
   latency and energy on the physical phone.

## Limits and deferred work

- The new context layer is not clinical validation, and the 160–200 cm test grid is arithmetic
  coverage, not evidence that every extreme of body size was represented in the source cohorts.
- Legacy canonical storage namespaces do not preserve the physical sensor or software version for
  every historical row. The feature separates known namespaces and methods; it cannot recreate
  missing provenance. Existing scoring/HealthKit writeback and unrelated legacy screens retain
  their incumbent algorithms and must not be represented as newly research-validated.
- Bedtime variation uses the longest eligible session per local wake date. It is a descriptive
  timing measure, not a circadian diagnosis or the published Sleep Regularity Index.
- Workout-matched comparisons, journal associations, training prescriptions, causal claims,
  free-form AI advice, journal parsing and read-only AI chat remain later plan increments. The
  initial release deliberately withholds actions whose input/method applicability is unproven.
- Physical-device validation is required in addition to package tests and compilation.
