import XCTest
@testable import HealthExporter

final class HealthMetricConfigTests: XCTestCase {

    // MARK: - HealthMetrics static properties

    func testWeight_hasExpectedName() {
        XCTAssertEqual(HealthMetrics.weight.name, "Weight")
    }

    func testSteps_hasExpectedName() {
        XCTAssertEqual(HealthMetrics.steps.name, "Steps")
    }

    func testGlucose_hasExpectedName() {
        XCTAssertEqual(HealthMetrics.glucose.name, "Blood Glucose")
    }

    // MARK: - LOINCCode constants

    func testLOINCCode_hemoglobinA1C_isCorrect() {
        XCTAssertEqual(LOINCCode.hemoglobinA1C, "4548-4",
            "LOINC code for Hemoglobin A1C should be 4548-4")
    }

    func testLOINCCode_lipidPanelConstants_areCorrect() {
        XCTAssertEqual(LOINCCode.totalCholesterol, "2093-3")
        XCTAssertEqual(LOINCCode.hdlCholesterol, "2085-9")
        XCTAssertEqual(LOINCCode.ldlCholesterolDirect, "2089-1")
        XCTAssertEqual(LOINCCode.triglycerides, "2571-8")
    }

    func testLOINCCode_cbcConstants_areCorrect() {
        XCTAssertEqual(LOINCCode.whiteBloodCellCount, "6690-2")
        XCTAssertEqual(LOINCCode.redBloodCellCount, "789-8")
        XCTAssertEqual(LOINCCode.hemoglobin, "718-7")
        XCTAssertEqual(LOINCCode.hematocrit, "4544-3")
        XCTAssertEqual(LOINCCode.platelets, "777-3")
        XCTAssertEqual(LOINCCode.meanCorpuscularVolume, "787-2")
        XCTAssertEqual(LOINCCode.meanCorpuscularHemoglobin, "785-6")
        XCTAssertEqual(LOINCCode.meanCorpuscularHemoglobinConcentration, "786-4")
        XCTAssertEqual(LOINCCode.redCellDistributionWidth, "788-0")
    }

    func testLOINCCode_cmpAndThyroidConstants_areCorrect() {
        XCTAssertEqual(LOINCCode.fastingGlucose, "1558-6")
        XCTAssertEqual(LOINCCode.bloodUreaNitrogen, "3094-0")
        XCTAssertEqual(LOINCCode.creatinine, "2160-0")
        XCTAssertEqual(LOINCCode.estimatedGlomerularFiltrationRate, "33914-3")
        XCTAssertEqual(LOINCCode.sodium, "2951-2")
        XCTAssertEqual(LOINCCode.potassium, "2823-3")
        XCTAssertEqual(LOINCCode.chloride, "2075-0")
        XCTAssertEqual(LOINCCode.carbonDioxideBicarbonate, "2028-9")
        XCTAssertEqual(LOINCCode.calcium, "17861-6")
        XCTAssertEqual(LOINCCode.totalProtein, "2885-2")
        XCTAssertEqual(LOINCCode.albumin, "1751-7")
        XCTAssertEqual(LOINCCode.bilirubinTotal, "1975-2")
        XCTAssertEqual(LOINCCode.alanineAminotransferase, "1742-6")
        XCTAssertEqual(LOINCCode.aspartateAminotransferase, "1920-8")
        XCTAssertEqual(LOINCCode.alkalinePhosphatase, "6768-6")
        XCTAssertEqual(LOINCCode.thyroidStimulatingHormone, "3016-3")
        XCTAssertEqual(LOINCCode.freeT4, "3024-7")
        XCTAssertEqual(LOINCCode.freeT3, "3051-0")
    }

    func testLOINCCode_otherLabConstants_areCorrect() {
        XCTAssertEqual(LOINCCode.vitaminD25Hydroxy, "1989-3")
        XCTAssertEqual(LOINCCode.vitaminB12, "2132-9")
        XCTAssertEqual(LOINCCode.ferritin, "2276-4")
        XCTAssertEqual(LOINCCode.iron, "2498-4")
        XCTAssertEqual(LOINCCode.totalIronBindingCapacity, "2500-7")
        XCTAssertEqual(LOINCCode.highSensitivityCRP, "30522-7")
    }
}
