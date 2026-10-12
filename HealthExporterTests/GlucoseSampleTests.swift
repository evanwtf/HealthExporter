import Foundation
@testable import HealthExporter
import HealthKit
import Testing

struct GlucoseSampleTests {
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

    @Test func init_normalBloodGlucose_succeeds() {
        let result = GlucoseSampleMgDl(from: makeSample(value: 120.0))
        #expect(result != nil)
        #expect(result?.value == 120.0)
    }

    @Test func init_valueExactlyAt20_succeeds() {
        let result = GlucoseSampleMgDl(from: makeSample(value: 20.0))
        #expect(result != nil, "Value of exactly 20 mg/dL should be accepted")
    }

    @Test func init_valueJustAbove20_succeeds() {
        let result = GlucoseSampleMgDl(from: makeSample(value: 20.1))
        #expect(result != nil)
    }

    @Test func init_highGlucoseValue_succeeds() {
        let result = GlucoseSampleMgDl(from: makeSample(value: 500.0))
        #expect(result != nil)
        #expect(result?.value == 500.0)
    }

    @Test func init_minimumDiabeticallyRelevantValue_succeeds() {
        // 70 mg/dL is the low end of normal range
        let result = GlucoseSampleMgDl(from: makeSample(value: 70.0))
        #expect(result != nil)
    }

    // MARK: - Rejected values (< 20 threshold)

    @Test func init_valueJustBelow20_returnsNil() {
        let result = GlucoseSampleMgDl(from: makeSample(value: 19.9))
        #expect(result == nil, "Value just below 20 mg/dL should be rejected")
    }

    @Test func init_zeroValue_returnsNil() {
        let result = GlucoseSampleMgDl(from: makeSample(value: 0.0))
        #expect(result == nil, "Zero value should be rejected")
    }

    @Test func init_a1cPercentageMisread_returnsNil() {
        // A1C of 7.2% stored as mg/dL would be 7.2, which is < 20
        let result = GlucoseSampleMgDl(from: makeSample(value: 7.2))
        #expect(result == nil, "A1C percentage value (7.2) misread as mg/dL should be rejected")
    }

    @Test func init_lowPercentageMisread_returnsNil() {
        // Very small value that could be a percentage stored as decimal (e.g. 0.072 = 7.2%)
        let result = GlucoseSampleMgDl(from: makeSample(value: 0.072))
        #expect(result == nil)
    }

    @Test func init_a1cHighEndMisread_returnsNil() {
        // Even a high A1C of 14% is still < 20 mg/dL
        let result = GlucoseSampleMgDl(from: makeSample(value: 14.0))
        #expect(result == nil)
    }

    // MARK: - Date preservation

    @Test func init_preservesStartDate() {
        let referenceDate = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let hkSample = HKQuantitySample(
            type: glucoseType,
            quantity: HKQuantity(unit: mgDlUnit, doubleValue: 100.0),
            start: referenceDate,
            end: referenceDate
        )
        let result = GlucoseSampleMgDl(from: hkSample)
        #expect(result?.startDate == referenceDate)
    }

    // MARK: - Value accuracy

    @Test func init_valueIsPreservedAccurately() {
        let expectedValue = 183.5
        guard let result = GlucoseSampleMgDl(from: makeSample(value: expectedValue)) else {
            Issue.record("GlucoseSampleMgDl should be created for value \(expectedValue)")
            return
        }
        #expect(abs(result.value - expectedValue) <= 0.001)
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

    @Test func init_preprandialMetadata_setsBeforeMeal() {
        let sample = makeSample(value: 98, metadata: [HKMetadataKeyBloodGlucoseMealTime: NSNumber(value: HKBloodGlucoseMealTime.preprandial.rawValue)])
        #expect(GlucoseSampleMgDl(from: sample)?.mealTime == .preprandial)
    }

    @Test func init_postprandialMetadata_setsAfterMeal() {
        let sample = makeSample(value: 140, metadata: [HKMetadataKeyBloodGlucoseMealTime: NSNumber(value: HKBloodGlucoseMealTime.postprandial.rawValue)])
        #expect(GlucoseSampleMgDl(from: sample)?.mealTime == .postprandial)
    }

    @Test func init_noMetadata_mealTimeIsNil() {
        let result = GlucoseSampleMgDl(from: makeSample(value: 110, metadata: nil))
        #expect(result != nil)
        #expect(result?.mealTime == nil)
    }

    /// HealthKit rejects an unknown meal-time value when the sample is created,
    /// so the mapping is tested directly on the metadata dictionary.
    @Test func mealTimeFromMetadata_unknownRawValue_isNil() {
        #expect(GlucoseSampleMgDl.mealTime(fromMetadata: [HKMetadataKeyBloodGlucoseMealTime: NSNumber(value: 99)]) == nil)
        #expect(GlucoseSampleMgDl.mealTime(fromMetadata: [HKMetadataKeyBloodGlucoseMealTime: NSNumber(value: 0)]) == nil)
    }

    @Test func mealTimeFromMetadata_nonNumberValue_isNil() {
        #expect(GlucoseSampleMgDl.mealTime(fromMetadata: [HKMetadataKeyBloodGlucoseMealTime: "before"]) == nil)
    }

    @Test func mealTimeFromMetadata_knownRawValues() {
        #expect(GlucoseSampleMgDl.mealTime(fromMetadata: [HKMetadataKeyBloodGlucoseMealTime: NSNumber(value: 1)]) == .preprandial)
        #expect(GlucoseSampleMgDl.mealTime(fromMetadata: [HKMetadataKeyBloodGlucoseMealTime: NSNumber(value: 2)]) == .postprandial)
    }
}
