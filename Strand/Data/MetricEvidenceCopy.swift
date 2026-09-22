import Foundation
import StrandAnalytics

enum MetricEvidenceCopy {
    static func explanation(_ key: String) -> String {
        switch MetricEvidence.group(for: key) {
        case .pulse: return String(localized: "Optical heart-rate estimate. WHOOP 4 studies support resting and overnight use; movement, fit and sampling affect daily averages and peaks. NOOP has not been clinically validated.")
        case .hrv: return String(localized: "Trends only: compare the same source, recording window and HRV method. WHOOP validation does not validate NOOP's R–R processing. RMSSD and Apple Health SDNN are not interchangeable.")
        case .oxygen, .respiration: return String(localized: "NOOP's raw WHOOP 4 oxygen and respiration fields are uncalibrated. Do not interpret them as percentages or breaths per minute. Imported values depend on their original device and algorithm.")
        case .temperature: return String(localized: "Trends only. NOOP's WHOOP 4 skin-temperature conversion is provisional. Wrist temperature and baseline deviations are not core temperature or fever measurements.")
        case .sleep: return String(localized: "Sleep estimates, not a sleep study. WHOOP 4 validation tested WHOOP software, not NOOP. Quiet wakefulness and sparse motion can distort duration and efficiency; review the timing before acting.")
        case .stages: return String(localized: "Trends only, with substantial uncertainty. Deep, REM, light and restorative sleep depend on staging algorithms. Do not chase stage percentages or diagnose a sleep problem from these estimates.")
        case .sleepModel: return String(localized: "Model estimates: sleep need, debt and consistency are not measured biological requirements. Use recorded sleep timing and age-based guidance; a score cannot establish a precise sleep deficit.")
        case .energy: return String(localized: "Trends only. Heart-rate calorie formulas have individual error and limited exercise validation. Do not use estimated burn as an exact food allowance or calorie deficit.")
        case .score: return String(localized: "Descriptive algorithm score, with no validated healthy range. Charge, Effort, Rest, Vitality and stress do not diagnose illness, psychological stress or safe training capacity.")
        case .fitness: return String(localized: "Model estimate, not a fitness test or biological age. Heart-rate ratio research in trained men does not validate every person or NOOP's full model. Apple Health estimates retain their original method's limits.")
        case .steps: return String(localized: "Recorded step estimate: prefer a consistently carried phone or watch. WHOOP 4 does not supply a measured step count through NOOP's BLE path. More steps can be useful without a universal 10,000-step target.")
        case .motionSteps: return String(localized: "Trends only. WHOOP 4 motion is calibrated to phone steps; arm movement, missing wear and calibration changes affect the estimate. It is not a pedometer or a basis for precise step targets.")
        case .activity: return String(localized: "Recorded activity, not proof of guideline completion. HR zones depend on estimated maximum heart rate and are not automatically moderate or vigorous minutes. Strength minutes do not establish muscle-group coverage.")
        case .body: return String(localized: "Imported measurement, not measured by WHOOP. Accuracy depends on the scale and method. Weight, bioimpedance body fat and lean mass have different uncertainties; compare consistent conditions.")
        case .bmi: return String(localized: "BMI is a height-and-weight screening measure, not a direct body-fat or fitness measurement. Muscularity and individual context matter; it does not define a personal ideal weight.")
        case .nutrition: return String(localized: "Food-log estimate, not a strap measurement. Missing entries, portions and food databases affect accuracy. No calorie or macronutrient prescription is inferred from these records.")
        case .mood: return String(localized: "Personal check-in, not a clinical assessment. Compare your own entries over time; a mood score or its correlation with a wearable signal does not identify a cause.")
        case .unknown: return String(localized: "Accuracy and applicability have not been established for this metric. No normal range or advice is inferred.")
        }
    }
}
