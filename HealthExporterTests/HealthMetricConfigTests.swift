import Foundation
import Testing
@testable import HealthExporter

struct HealthMetricConfigTests {

    // MARK: - HealthMetrics static properties

    @Test func weight_hasExpectedName() {
        #expect(HealthMetrics.weight.name == "Weight")
    }

    @Test func steps_hasExpectedName() {
        #expect(HealthMetrics.steps.name == "Steps")
    }

    @Test func glucose_hasExpectedName() {
        #expect(HealthMetrics.glucose.name == "Blood Glucose")
    }

    // MARK: - LOINCCode constants

    @Test func loincCode_hemoglobinA1C_isCorrect() {
        #expect(LOINCCode.hemoglobinA1C == "4548-4", "LOINC code for Hemoglobin A1C should be 4548-4")
    }

    @Test func loincCode_lipidPanelConstants_areCorrect() {
        #expect(LOINCCode.totalCholesterol == "2093-3")
        #expect(LOINCCode.hdlCholesterol == "2085-9")
        #expect(LOINCCode.ldlCholesterolDirect == "2089-1")
        #expect(LOINCCode.triglycerides == "2571-8")
    }

    @Test func loincCode_cbcConstants_areCorrect() {
        #expect(LOINCCode.whiteBloodCellCount == "6690-2")
        #expect(LOINCCode.redBloodCellCount == "789-8")
        #expect(LOINCCode.hemoglobin == "718-7")
        #expect(LOINCCode.hematocrit == "4544-3")
        #expect(LOINCCode.platelets == "777-3")
        #expect(LOINCCode.meanCorpuscularVolume == "787-2")
        #expect(LOINCCode.meanCorpuscularHemoglobin == "785-6")
        #expect(LOINCCode.meanCorpuscularHemoglobinConcentration == "786-4")
        #expect(LOINCCode.redCellDistributionWidth == "788-0")
    }

    @Test func loincCode_cmpAndThyroidConstants_areCorrect() {
        #expect(LOINCCode.fastingGlucose == "1558-6")
        #expect(LOINCCode.bloodUreaNitrogen == "3094-0")
        #expect(LOINCCode.creatinine == "2160-0")
        #expect(LOINCCode.estimatedGlomerularFiltrationRate == "33914-3")
        #expect(LOINCCode.sodium == "2951-2")
        #expect(LOINCCode.potassium == "2823-3")
        #expect(LOINCCode.chloride == "2075-0")
        #expect(LOINCCode.carbonDioxideBicarbonate == "2028-9")
        #expect(LOINCCode.calcium == "17861-6")
        #expect(LOINCCode.totalProtein == "2885-2")
        #expect(LOINCCode.albumin == "1751-7")
        #expect(LOINCCode.bilirubinTotal == "1975-2")
        #expect(LOINCCode.alanineAminotransferase == "1742-6")
        #expect(LOINCCode.aspartateAminotransferase == "1920-8")
        #expect(LOINCCode.alkalinePhosphatase == "6768-6")
        #expect(LOINCCode.thyroidStimulatingHormone == "3016-3")
        #expect(LOINCCode.freeT4 == "3024-7")
        #expect(LOINCCode.freeT3 == "3051-0")
    }

    @Test func loincCode_otherLabConstants_areCorrect() {
        #expect(LOINCCode.vitaminD25Hydroxy == "1989-3")
        #expect(LOINCCode.vitaminB12 == "2132-9")
        #expect(LOINCCode.ferritin == "2276-4")
        #expect(LOINCCode.iron == "2498-4")
        #expect(LOINCCode.totalIronBindingCapacity == "2500-7")
        #expect(LOINCCode.highSensitivityCRP == "30522-7")
    }
}
