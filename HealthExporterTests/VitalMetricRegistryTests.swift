import Foundation
import Testing
import HealthKit
@testable import HealthExporter

struct VitalMetricRegistryTests {

    @Test func vitalMetric_containsExpectedCases() {
        #expect(Set(VitalMetric.allCases) == Set([
                .bloodPressure,
                .restingHeartRate,
                .heartRateVariabilitySDNN,
                .oxygenSaturation,
                .respiratoryRate,
                .bodyTemperature
            ]))
    }

    @Test func bloodPressureExpandsToSystolicAndDiastolicComponents() {
        #expect(VitalMetric.bloodPressure.components == [.bloodPressureSystolic, .bloodPressureDiastolic])
    }

    @Test func vitalComponentsHaveUniqueRawValues() {
        let rawValues = VitalMetricComponent.allCases.map(\.rawValue)
        #expect(Set(rawValues).count == rawValues.count)
    }

    @Test func vitalComponentHealthKitIdentifiers() {
        #expect(VitalMetricComponent.bloodPressureSystolic.healthKitIdentifier == .bloodPressureSystolic)
        #expect(VitalMetricComponent.bloodPressureDiastolic.healthKitIdentifier == .bloodPressureDiastolic)
        #expect(VitalMetricComponent.restingHeartRate.healthKitIdentifier == .restingHeartRate)
        #expect(VitalMetricComponent.heartRateVariabilitySDNN.healthKitIdentifier == .heartRateVariabilitySDNN)
        #expect(VitalMetricComponent.oxygenSaturation.healthKitIdentifier == .oxygenSaturation)
        #expect(VitalMetricComponent.respiratoryRate.healthKitIdentifier == .respiratoryRate)
        #expect(VitalMetricComponent.bodyTemperature.healthKitIdentifier == .bodyTemperature)
    }

    @Test func oxygenSaturationConvertsHealthKitFractionToPercent() {
        let quantity = HKQuantity(unit: .percent(), doubleValue: 0.985)
        let result = VitalMetricComponent.oxygenSaturation.valueAndUnit(from: quantity, temperatureUnit: .fahrenheit)

        #expect(abs(result.value - 98.5) <= 0.0001)
        #expect(result.unit == "%")
    }

    @Test func bodyTemperatureUsesSelectedUnit() {
        let quantity = HKQuantity(unit: .degreeCelsius(), doubleValue: 37.0)
        let fahrenheit = VitalMetricComponent.bodyTemperature.valueAndUnit(from: quantity, temperatureUnit: .fahrenheit)
        let celsius = VitalMetricComponent.bodyTemperature.valueAndUnit(from: quantity, temperatureUnit: .celsius)

        #expect(abs(fahrenheit.value - 98.6) <= 0.01)
        #expect(fahrenheit.unit == "°F")
        #expect(abs(celsius.value - 37.0) <= 0.01)
        #expect(celsius.unit == "°C")
    }
}
