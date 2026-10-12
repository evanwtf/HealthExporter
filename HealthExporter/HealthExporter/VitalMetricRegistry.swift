import HealthKit

/// Higher-level vitals users can select in the export UI.
/// Some selections expand to multiple CSV rows, such as Blood Pressure.
nonisolated enum VitalMetric: String, CaseIterable, Codable, Identifiable, Hashable {
    case bloodPressure
    case restingHeartRate
    case heartRateVariabilitySDNN
    case oxygenSaturation
    case respiratoryRate
    case bodyTemperature

    static let allCasesSet: Set<VitalMetric> = Set(allCases)

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .bloodPressure: "Blood Pressure"
        case .restingHeartRate: "Resting Heart Rate"
        case .heartRateVariabilitySDNN: "Heart Rate Variability (SDNN)"
        case .oxygenSaturation: "Oxygen Saturation (SpO₂)"
        case .respiratoryRate: "Respiratory Rate"
        case .bodyTemperature: "Body Temperature"
        }
    }

    var components: [VitalMetricComponent] {
        switch self {
        case .bloodPressure:
            [.bloodPressureSystolic, .bloodPressureDiastolic]
        case .restingHeartRate:
            [.restingHeartRate]
        case .heartRateVariabilitySDNN:
            [.heartRateVariabilitySDNN]
        case .oxygenSaturation:
            [.oxygenSaturation]
        case .respiratoryRate:
            [.respiratoryRate]
        case .bodyTemperature:
            [.bodyTemperature]
        }
    }
}

/// Concrete HealthKit quantity rows emitted for selected vitals.
nonisolated enum VitalMetricComponent: String, CaseIterable, Identifiable, Hashable {
    case bloodPressureSystolic
    case bloodPressureDiastolic
    case restingHeartRate
    case heartRateVariabilitySDNN
    case oxygenSaturation
    case respiratoryRate
    case bodyTemperature

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .bloodPressureSystolic: "Blood Pressure Systolic"
        case .bloodPressureDiastolic: "Blood Pressure Diastolic"
        case .restingHeartRate: "Resting Heart Rate"
        case .heartRateVariabilitySDNN: "Heart Rate Variability (SDNN)"
        case .oxygenSaturation: "Oxygen Saturation"
        case .respiratoryRate: "Respiratory Rate"
        case .bodyTemperature: "Body Temperature"
        }
    }

    var healthKitIdentifier: HKQuantityTypeIdentifier {
        switch self {
        case .bloodPressureSystolic: .bloodPressureSystolic
        case .bloodPressureDiastolic: .bloodPressureDiastolic
        case .restingHeartRate: .restingHeartRate
        case .heartRateVariabilitySDNN: .heartRateVariabilitySDNN
        case .oxygenSaturation: .oxygenSaturation
        case .respiratoryRate: .respiratoryRate
        case .bodyTemperature: .bodyTemperature
        }
    }

    var valuePrecision: Int {
        switch self {
        case .bodyTemperature, .oxygenSaturation, .respiratoryRate:
            1
        case .bloodPressureSystolic, .bloodPressureDiastolic, .restingHeartRate, .heartRateVariabilitySDNN:
            0
        }
    }

    func valueAndUnit(from quantity: HKQuantity, temperatureUnit: TemperatureUnit) -> (value: Double, unit: String) {
        switch self {
        case .bloodPressureSystolic, .bloodPressureDiastolic:
            (quantity.doubleValue(for: HKUnit.millimeterOfMercury()), "mmHg")
        case .restingHeartRate:
            (quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute())), "bpm")
        case .heartRateVariabilitySDNN:
            (quantity.doubleValue(for: HKUnit.secondUnit(with: .milli)), "ms")
        case .oxygenSaturation:
            (quantity.doubleValue(for: HKUnit.percent()) * 100, "%")
        case .respiratoryRate:
            (quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute())), "breaths/min")
        case .bodyTemperature:
            switch temperatureUnit {
            case .celsius:
                (quantity.doubleValue(for: HKUnit.degreeCelsius()), "°C")
            case .fahrenheit:
                (quantity.doubleValue(for: HKUnit.degreeFahrenheit()), "°F")
            }
        }
    }
}
