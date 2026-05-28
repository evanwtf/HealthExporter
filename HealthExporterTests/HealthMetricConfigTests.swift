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
}
