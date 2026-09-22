import XCTest
@testable import StrandAnalytics

/// Arithmetic checks against published equations, not clinical validation of wearable estimates.
final class MetricResearchRegressionTests: XCTestCase {
    func testRestingEnergyMatchesRozaShizgalTableThreeAcrossRequestedMaleProfiles() {
        // Roza & Shizgal (1984), Table 3 equation 3, height in cm, output kcal/day.
        // https://zakboekdietetiek.nl/wp-content/uploads/2015/06/roza-1984.pdf
        for (age, height, weight, expected) in [(20.0,160.0,60.0,1546.482),
                                               (30,180,80,1853.632), (40,200,100,2160.782)] {
            let actual = Calories.restingKcalPerS(Calories.male, weightKg: weight, heightCm: height, age: age) * 86400
            XCTAssertEqual(actual, expected, accuracy: 0.000001)
        }
        // The paper's worked Table 4 example rounds 1558.132 to 1558 kcal/day.
        XCTAssertEqual(Calories.restingKcalPerS(Calories.male, weightKg: 70, heightCm: 170, age: 50) * 86400,
                       1558.132, accuracy: 0.000001)
        for age in 20...40 {
            for height in 160...200 {
                let actual = Calories.restingKcalPerS(Calories.male, weightKg: 80,
                                                     heightCm: Double(height), age: Double(age)) * 86400
                // Independent cm-based reference catches the implementation's metre conversion.
                let reference = 88.362 + 4.799 * Double(height) + 13.397 * 80 - 5.677 * Double(age)
                XCTAssertEqual(actual, reference, accuracy: 0.000001)
            }
        }
    }

    func testTanakaPopulationPredictionForAgeTwentyToForty() {
        // Tanaka et al. 2001, doi:10.1016/S0735-1097(00)01054-8: 208 - 0.7*age.
        for (age, expected) in [(20.0,194.0),(25,190.5),(30,187),(35,183.5),(40,180)] {
            XCTAssertEqual(StrainScorer.tanakaHRmax(age: age), expected, accuracy: 0.000001)
        }
    }

    func testMaleExerciseEnergyMatchesKeytelBaseEquationAndUnits() {
        // Keytel et al. 2005, Table V, doi:10.1080/02640410470001730089.
        // The original returns kJ/min. These independently evaluated literals are kcal/min.
        for (age, weight, hr, expected) in [(20.0,60.0,100.0,5.725406309751435),
                                           (30,80,130,11.681429254302104),
                                           (40,100,160,17.637452198852774)] {
            let actual = Calories.activeKcalPerS(Calories.male, hr: hr, hrmax: 200,
                                                 weightKg: weight, age: age) * 60
            XCTAssertEqual(actual, expected, accuracy: 0.000001)
        }
    }

    func testFitnessAdjustedCaloriesBoundExistingCoefficientRoundingAgainstPublishedTable() {
        // Table III has four decimal places; the incumbent uses rounded three-place slopes.
        // This tolerates that documented arithmetic difference, not individual prediction error.
        // Supplying Uth-estimated VO2max instead of measured VO2max is NOT validated by this test.
        for (age, weight, hr, vo2, expected) in [(20.0,60.0,100.0,35.0,2.604804015296367),
                                                (30,80,130,45,10.652844168260039),
                                                (40,100,160,55,18.700884321223707)] {
            let actual = Calories.activeKcalPerS(Calories.male, hr: hr, hrmax: 200,
                weightKg: weight, age: age, vo2max: vo2) * 60
            XCTAssertEqual(actual, expected, accuracy: 0.03)
        }
    }
}
