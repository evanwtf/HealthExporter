import HealthKit

/// Higher-level vitals users can select in the export UI.
/// Some selections expand to multiple CSV rows, such as Blood Pressure.
enum VitalMetric: String, CaseIterable, Codable, Identifiable, Hashable {
    case bloodPressure
    case restingHeartRate
    case heartRateVariabilitySDNN
    case oxygenSaturation
    case respiratoryRate
    case bodyTemperature

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bloodPressure: return "Blood Pressure"
        case .restingHeartRate: return "Resting Heart Rate"
        case .heartRateVariabilitySDNN: return "Heart Rate Variability (SDNN)"
        case .oxygenSaturation: return "Oxygen Saturation (SpO₂)"
        case .respiratoryRate: return "Respiratory Rate"
        case .bodyTemperature: return "Body Temperature"
        }
    }

    var components: [VitalMetricComponent] {
        switch self {
        case .bloodPressure:
            return [.bloodPressureSystolic, .bloodPressureDiastolic]
        case .restingHeartRate:
            return [.restingHeartRate]
        case .heartRateVariabilitySDNN:
            return [.heartRateVariabilitySDNN]
        case .oxygenSaturation:
            return [.oxygenSaturation]
        case .respiratoryRate:
            return [.respiratoryRate]
        case .bodyTemperature:
            return [.bodyTemperature]
        }
    }
}

/// Concrete HealthKit quantity rows emitted for selected vitals.
enum VitalMetricComponent: String, CaseIterable, Identifiable, Hashable {
    case bloodPressureSystolic
    case bloodPressureDiastolic
    case restingHeartRate
    case heartRateVariabilitySDNN
    case oxygenSaturation
    case respiratoryRate
    case bodyTemperature

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bloodPressureSystolic: return "Blood Pressure Systolic"
        case .bloodPressureDiastolic: return "Blood Pressure Diastolic"
        case .restingHeartRate: return "Resting Heart Rate"
        case .heartRateVariabilitySDNN: return "Heart Rate Variability (SDNN)"
        case .oxygenSaturation: return "Oxygen Saturation"
        case .respiratoryRate: return "Respiratory Rate"
        case .bodyTemperature: return "Body Temperature"
        }
    }

    var healthKitIdentifier: HKQuantityTypeIdentifier {
        switch self {
        case .bloodPressureSystolic: return .bloodPressureSystolic
        case .bloodPressureDiastolic: return .bloodPressureDiastolic
        case .restingHeartRate: return .restingHeartRate
        case .heartRateVariabilitySDNN: return .heartRateVariabilitySDNN
        case .oxygenSaturation: return .oxygenSaturation
        case .respiratoryRate: return .respiratoryRate
        case .bodyTemperature: return .bodyTemperature
        }
    }

    var valuePrecision: Int {
        switch self {
        case .bodyTemperature, .oxygenSaturation, .respiratoryRate:
            return 1
        case .bloodPressureSystolic, .bloodPressureDiastolic, .restingHeartRate, .heartRateVariabilitySDNN:
            return 0
        }
    }

    func valueAndUnit(from quantity: HKQuantity, temperatureUnit: TemperatureUnit) -> (value: Double, unit: String) {
        switch self {
        case .bloodPressureSystolic, .bloodPressureDiastolic:
            return (quantity.doubleValue(for: HKUnit.millimeterOfMercury()), "mmHg")
        case .restingHeartRate:
            return (quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute())), "bpm")
        case .heartRateVariabilitySDNN:
            return (quantity.doubleValue(for: HKUnit.secondUnit(with: .milli)), "ms")
        case .oxygenSaturation:
            return (quantity.doubleValue(for: HKUnit.percent()) * 100, "%")
        case .respiratoryRate:
            return (quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute())), "breaths/min")
        case .bodyTemperature:
            switch temperatureUnit {
            case .celsius:
                return (quantity.doubleValue(for: HKUnit.degreeCelsius()), "°C")
            case .fahrenheit:
                return (quantity.doubleValue(for: HKUnit.degreeFahrenheit()), "°F")
            }
        }
    }
}
