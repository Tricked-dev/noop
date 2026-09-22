import Foundation

/// Evidence applicability, separate from physiological calculations and stored metric values.
/// A published WHOOP algorithm validation never establishes accuracy of NOOP's pipeline.
public enum MetricEvidence {
    public enum Group: String, CaseIterable, Sendable {
        case pulse, hrv, oxygen, respiration, temperature, sleep, stages, sleepModel
        case energy, score, fitness, steps, motionSteps, activity, body, bmi, nutrition, mood, unknown
    }
    public static func group(for key: String) -> Group {
        switch key {
        case "avg_hr", "max_hr", "rhr": return .pulse
        case "hrv": return .hrv
        case "spo2": return .oxygen
        case "resp_rate": return .respiration
        case "skin_temp": return .temperature
        case "sleep_total_min", "in_bed_min", "sleep_efficiency": return .sleep
        case "sleep_deep_min", "sleep_rem_min", "sleep_light_min", "restorative_min", "restorative_pct": return .stages
        case "sleep_need_min", "sleep_debt_min", "hours_vs_needed_pct", "sleep_consistency": return .sleepModel
        case "energy_kcal", "active_kcal": return .energy
        case "recovery", "strain", "stress", "vitality", "sleep_performance", "sleep_score": return .score
        case "vo2max", "vo2max_est", "fitness_age", "body_age": return .fitness
        case "steps": return .steps
        case "steps_est": return .motionSteps
        case "hr_zones13_min", "hr_zones45_min", "hr_zones_all_min", "strength_min", "intensity_min": return .activity
        case "weight", "body_fat", "lean_mass": return .body
        case "bmi": return .bmi
        case "calories_in", "protein_g", "carbs_g", "fat_g": return .nutrition
        case "mood": return .mood
        default: return .unknown
        }
    }

    public static func references(for group: Group) -> [String] {
        switch group {
        case .pulse, .hrv: return ["https://pubmed.ncbi.nlm.nih.gov/40834291/", "https://doi.org/10.3390/s24216826"]
        case .sleep, .stages: return ["https://doi.org/10.1093/sleepadvances/zpaf021", "https://www.cdc.gov/sleep/about/"]
        case .sleepModel: return ["https://www.cdc.gov/sleep/about/"]
        case .energy: return ["https://pubmed.ncbi.nlm.nih.gov/15966347/"]
        case .fitness: return ["https://pubmed.ncbi.nlm.nih.gov/14624296/"]
        case .steps, .motionSteps: return ["https://pubmed.ncbi.nlm.nih.gov/40713949/"]
        case .activity, .score: return ["https://www.who.int/publications/i/item/9789240015128"]
        case .body: return ["https://pubmed.ncbi.nlm.nih.gov/33929337/"]
        case .bmi: return ["https://www.cdc.gov/bmi/faq/"]
        case .oxygen: return ["https://www.fda.gov/medical-devices/products-and-medical-procedures/pulse-oximeters"]
        default: return [] // No unrelated citation presented as validation.
        }
    }

    /// Sensitive channels use the existing quality-aware MetricContext path instead of a second
    /// generic comparison. Estimator changes and uncalibrated fields must never look comparable.
    public static func allowsGenericComparison(_ key: String) -> Bool {
        !["rhr", "hrv", "resp_rate", "spo2", "skin_temp", "sleep_total_min", "vo2max_est",
          "fitness_age", "body_age"].contains(key) && group(for: key) != .unknown
    }
}
