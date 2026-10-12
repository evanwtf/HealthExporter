import XCTest
import HealthKit
@testable import HealthExporter

final class GlucoseSampleTests: XCTestCase {

    private let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!
    private let mgDlUnit = HKUnit.gramUnit(with: .milli).unitDivided(by: HKUnit.literUnit(with: .deci))

    private func makeSample(value: Double, date: Date = Date()) -> HKQuantitySample {
        HKQuantitySample(
            type: glucoseType,
            quantity: HKQuantity(unit: mgDlUnit, doubleValue: value),
            start: date,
            end: date
        )
    }

    // MARK: - Accepted values

    func testInit_normalBloodGlucose_succeeds() {
        let result = GlucoseSampleMgDl(from: makeSample(value: 120.0))
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.value, 120.0)
    }

    func testInit_valueExactlyAt20_succeeds() {
        let result = GlucoseSampleMgDl(from: makeSample(value: 20.0))
        XCTAssertNotNil(result, "Value of exactly 20 mg/dL should be accepted")
    }

    func testInit_valueJustAbove20_succeeds() {
        let result = GlucoseSampleMgDl(from: makeSample(value: 20.1))
        XCTAssertNotNil(result)
    }

    func testInit_highGlucoseValue_succeeds() {
        let result = GlucoseSampleMgDl(from: makeSample(value: 500.0))
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.value, 500.0)
    }

    func testInit_minimumDiabeticallyRelevantValue_succeeds() {
        // 70 mg/dL is the low end of normal range
        let result = GlucoseSampleMgDl(from: makeSample(value: 70.0))
        XCTAssertNotNil(result)
    }

    // MARK: - Rejected values (< 20 threshold)

    func testInit_valueJustBelow20_returnsNil() {
        let result = GlucoseSampleMgDl(from: makeSample(value: 19.9))
        XCTAssertNil(result, "Value just below 20 mg/dL should be rejected")
    }

    func testInit_zeroValue_returnsNil() {
        let result = GlucoseSampleMgDl(from: makeSample(value: 0.0))
        XCTAssertNil(result, "Zero value should be rejected")
    }

    func testInit_a1cPercentageMisread_returnsNil() {
        // A1C of 7.2% stored as mg/dL would be 7.2, which is < 20
        let result = GlucoseSampleMgDl(from: makeSample(value: 7.2))
        XCTAssertNil(result, "A1C percentage value (7.2) misread as mg/dL should be rejected")
    }

    func testInit_lowPercentageMisread_returnsNil() {
        // Very small value that could be a percentage stored as decimal (e.g. 0.072 = 7.2%)
        let result = GlucoseSampleMgDl(from: makeSample(value: 0.072))
        XCTAssertNil(result)
    }

    func testInit_a1cHighEndMisread_returnsNil() {
        // Even a high A1C of 14% is still < 20 mg/dL
        let result = GlucoseSampleMgDl(from: makeSample(value: 14.0))
        XCTAssertNil(result)
    }

    // MARK: - Date preservation

    func testInit_preservesStartDate() {
        let referenceDate = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let hkSample = HKQuantitySample(
            type: glucoseType,
            quantity: HKQuantity(unit: mgDlUnit, doubleValue: 100.0),
            start: referenceDate,
            end: referenceDate
        )
        let result = GlucoseSampleMgDl(from: hkSample)
        XCTAssertEqual(result?.startDate, referenceDate)
    }

    // MARK: - Value accuracy

    func testInit_valueIsPreservedAccurately() {
        let expectedValue = 183.5
        guard let result = GlucoseSampleMgDl(from: makeSample(value: expectedValue)) else {
            XCTFail("GlucoseSampleMgDl should be created for value \(expectedValue)")
            return
        }
        XCTAssertEqual(result.value, expectedValue, accuracy: 0.001)
    }

    // MARK: - Meal time metadata

    private func makeSample(value: Double, metadata: [String: Any]?) -> HKQuantitySample {
        let date = Date(timeIntervalSinceReferenceDate: 1_000_000)
        return HKQuantitySample(
            type: glucoseType,
            quantity: HKQuantity(unit: mgDlUnit, doubleValue: value),
            start: date,
            end: date,
            metadata: metadata
        )
    }

    func testInit_preprandialMetadata_setsBeforeMeal() {
        let sample = makeSample(value: 98, metadata: [HKMetadataKeyBloodGlucoseMealTime: NSNumber(value: HKBloodGlucoseMealTime.preprandial.rawValue)])
        XCTAssertEqual(GlucoseSampleMgDl(from: sample)?.mealTime, .preprandial)
    }

    func testInit_postprandialMetadata_setsAfterMeal() {
        let sample = makeSample(value: 140, metadata: [HKMetadataKeyBloodGlucoseMealTime: NSNumber(value: HKBloodGlucoseMealTime.postprandial.rawValue)])
        XCTAssertEqual(GlucoseSampleMgDl(from: sample)?.mealTime, .postprandial)
    }

    func testInit_noMetadata_mealTimeIsNil() {
        let result = GlucoseSampleMgDl(from: makeSample(value: 110, metadata: nil))
        XCTAssertNotNil(result)
        XCTAssertNil(result?.mealTime)
    }

    // HealthKit rejects an unknown meal-time value when the sample is created,
    // so the mapping is tested directly on the metadata dictionary.
    func testMealTimeFromMetadata_unknownRawValue_isNil() {
        XCTAssertNil(GlucoseSampleMgDl.mealTime(fromMetadata: [HKMetadataKeyBloodGlucoseMealTime: NSNumber(value: 99)]))
        XCTAssertNil(GlucoseSampleMgDl.mealTime(fromMetadata: [HKMetadataKeyBloodGlucoseMealTime: NSNumber(value: 0)]))
    }

    func testMealTimeFromMetadata_nonNumberValue_isNil() {
        XCTAssertNil(GlucoseSampleMgDl.mealTime(fromMetadata: [HKMetadataKeyBloodGlucoseMealTime: "before"]))
    }

    func testMealTimeFromMetadata_knownRawValues() {
        XCTAssertEqual(GlucoseSampleMgDl.mealTime(fromMetadata: [HKMetadataKeyBloodGlucoseMealTime: NSNumber(value: 1)]), .preprandial)
        XCTAssertEqual(GlucoseSampleMgDl.mealTime(fromMetadata: [HKMetadataKeyBloodGlucoseMealTime: NSNumber(value: 2)]), .postprandial)
    }
}
