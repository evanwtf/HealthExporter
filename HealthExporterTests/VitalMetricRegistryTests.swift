import XCTest
import HealthKit
@testable import HealthExporter

final class VitalMetricRegistryTests: XCTestCase {

    func testVitalMetric_containsExpectedCases() {
        XCTAssertEqual(
            Set(VitalMetric.allCases),
            Set([
                .bloodPressure,
                .restingHeartRate,
                .heartRateVariabilitySDNN,
                .oxygenSaturation,
                .respiratoryRate,
                .bodyTemperature
            ])
        )
    }

    func testBloodPressureExpandsToSystolicAndDiastolicComponents() {
        XCTAssertEqual(VitalMetric.bloodPressure.components, [.bloodPressureSystolic, .bloodPressureDiastolic])
    }

    func testVitalComponentsHaveUniqueRawValues() {
        let rawValues = VitalMetricComponent.allCases.map(\.rawValue)
        XCTAssertEqual(Set(rawValues).count, rawValues.count)
    }

    func testVitalComponentHealthKitIdentifiers() {
        XCTAssertEqual(VitalMetricComponent.bloodPressureSystolic.healthKitIdentifier, .bloodPressureSystolic)
        XCTAssertEqual(VitalMetricComponent.bloodPressureDiastolic.healthKitIdentifier, .bloodPressureDiastolic)
        XCTAssertEqual(VitalMetricComponent.restingHeartRate.healthKitIdentifier, .restingHeartRate)
        XCTAssertEqual(VitalMetricComponent.heartRateVariabilitySDNN.healthKitIdentifier, .heartRateVariabilitySDNN)
        XCTAssertEqual(VitalMetricComponent.oxygenSaturation.healthKitIdentifier, .oxygenSaturation)
        XCTAssertEqual(VitalMetricComponent.respiratoryRate.healthKitIdentifier, .respiratoryRate)
        XCTAssertEqual(VitalMetricComponent.bodyTemperature.healthKitIdentifier, .bodyTemperature)
    }

    func testOxygenSaturationConvertsHealthKitFractionToPercent() {
        let quantity = HKQuantity(unit: .percent(), doubleValue: 0.985)
        let result = VitalMetricComponent.oxygenSaturation.valueAndUnit(from: quantity, temperatureUnit: .fahrenheit)

        XCTAssertEqual(result.value, 98.5, accuracy: 0.0001)
        XCTAssertEqual(result.unit, "%")
    }

    func testBodyTemperatureUsesSelectedUnit() {
        let quantity = HKQuantity(unit: .degreeCelsius(), doubleValue: 37.0)
        let fahrenheit = VitalMetricComponent.bodyTemperature.valueAndUnit(from: quantity, temperatureUnit: .fahrenheit)
        let celsius = VitalMetricComponent.bodyTemperature.valueAndUnit(from: quantity, temperatureUnit: .celsius)

        XCTAssertEqual(fahrenheit.value, 98.6, accuracy: 0.01)
        XCTAssertEqual(fahrenheit.unit, "°F")
        XCTAssertEqual(celsius.value, 37.0, accuracy: 0.01)
        XCTAssertEqual(celsius.unit, "°C")
    }
}
