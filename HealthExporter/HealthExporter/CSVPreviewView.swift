import SwiftUI

/// Shows the CSV header and one made-up example row per selected metric
/// category. It reads only the current selections; it never reads HealthKit.
struct CSVPreviewView: View {
    let exportWeight: Bool
    let exportSteps: Bool
    let exportGlucose: Bool
    let labMetrics: [LabMetric]
    let vitalMetrics: Set<VitalMetric>
    let weightUnit: WeightUnit
    let temperatureUnit: TemperatureUnit
    let dateFormat: DateFormatOption

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let maxRows = 4

    static var header: [String] {
        CSVGenerator.csvHeader.components(separatedBy: ",")
    }

    /// A fixed, made-up reading time. Rows step back one hour each.
    private static let exampleDate: Date = {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = 2026
        components.month = 3
        components.day = 14
        components.hour = 7
        components.minute = 42
        components.second = 5
        return components.date ?? Date(timeIntervalSince1970: 0)
    }()

    /// Plausible example values, keyed by `LabMetric.name`.
    private static let labExamples: [String: (value: Double, unit: String)] = [
        "Hemoglobin A1C": (5.6, "%"),
        "Total Cholesterol": (182, "mg/dL"),
        "HDL Cholesterol": (58, "mg/dL"),
        "LDL Cholesterol": (104, "mg/dL"),
        "Triglycerides": (96, "mg/dL"),
        "WBC": (6.2, "10*3/uL"),
        "RBC": (4.85, "10*6/uL"),
        "Hemoglobin": (14.2, "g/dL"),
        "Hematocrit": (42.1, "%"),
        "Platelets": (245, "10*3/uL"),
        "MCV": (88.4, "fL"),
        "MCH": (29.6, "pg"),
        "MCHC": (33.5, "g/dL"),
        "RDW": (12.9, "%"),
        "Glucose": (92, "mg/dL"),
        "BUN": (15, "mg/dL"),
        "Creatinine": (0.94, "mg/dL"),
        "eGFR": (96, "mL/min/1.73m2"),
        "Sodium": (140, "mmol/L"),
        "Potassium": (4.2, "mmol/L"),
        "Chloride": (102, "mmol/L"),
        "CO2 / Bicarbonate": (25, "mmol/L"),
        "Calcium": (9.5, "mg/dL"),
        "Total Protein": (7.1, "g/dL"),
        "Albumin": (4.4, "g/dL"),
        "Bilirubin Total": (0.6, "mg/dL"),
        "ALT": (22, "U/L"),
        "AST": (24, "U/L"),
        "Alkaline Phosphatase": (68, "U/L"),
        "TSH": (1.8, "mIU/L"),
        "Free T4": (1.2, "ng/dL"),
        "Free T3": (3.1, "pg/mL"),
        "25-OH Vitamin D": (34, "ng/mL"),
        "Vitamin B12": (520, "pg/mL"),
        "Ferritin": (110, "ng/mL"),
        "Iron": (95, "ug/dL"),
        "TIBC": (310, "ug/dL"),
        "hs-CRP": (0.8, "mg/L"),
    ]

    private var selectedMetricCount: Int {
        [exportWeight, exportSteps, exportGlucose].filter { $0 }.count
            + labMetrics.count
            + vitalMetrics.count
    }

    /// One example row per selected category, in export order.
    var exampleRows: [CSVGridView.Row] {
        let formatter = CSVGenerator.makeDateFormatter(for: dateFormat)
        var rows: [CSVGridView.Row] = []

        func add(_ id: String, metric: String, loinc: String = "", value: String,
                 unit: String, source: String, mealTime: String = "") {
            let date = Self.exampleDate.addingTimeInterval(TimeInterval(-3_600 * rows.count))
            rows.append(CSVGridView.Row(
                id: id,
                cells: [formatter.string(from: date), metric, loinc, value, unit, source, mealTime]
            ))
        }

        if exportWeight {
            let (value, unit) = weightUnit == .kilograms ? ("82.74", "kg") : ("182.40", "lbs")
            add("weight", metric: "Weight", value: value, unit: unit, source: "iPhone")
        }
        if exportSteps {
            add("steps", metric: "Steps", value: "8214", unit: "steps", source: "Apple Watch")
        }
        if exportGlucose {
            add("glucose", metric: "Blood Glucose", value: "98", unit: "mg/dL",
                source: "Glucose Meter", mealTime: "Before Meal")
        }
        let lab = labMetrics.first { $0.loincCode == LOINCCode.hemoglobinA1C } ?? labMetrics.first
        if let lab {
            let example = Self.labExamples[lab.name] ?? (1, "")
            add("lab", metric: lab.name, loinc: lab.loincCode,
                value: String(format: "%.\(lab.valuePrecision)f", example.value),
                unit: example.unit, source: "Health Records")
        }
        if let vital = VitalMetric.allCases.first(where: { vitalMetrics.contains($0) }),
           let component = vital.components.first {
            let (value, unit) = Self.vitalExample(component, temperatureUnit: temperatureUnit)
            add("vital", metric: component.displayName,
                value: String(format: "%.\(component.valuePrecision)f", value),
                unit: unit, source: "Apple Watch")
        }
        return Array(rows.prefix(Self.maxRows))
    }

    private static func vitalExample(_ component: VitalMetricComponent,
                                     temperatureUnit: TemperatureUnit) -> (Double, String) {
        switch component {
        case .bloodPressureSystolic: return (118, "mmHg")
        case .bloodPressureDiastolic: return (76, "mmHg")
        case .restingHeartRate: return (58, "bpm")
        case .heartRateVariabilitySDNN: return (42, "ms")
        case .oxygenSaturation: return (98, "%")
        case .respiratoryRate: return (14, "breaths/min")
        case .bodyTemperature:
            return temperatureUnit == .celsius ? (36.8, "°C") : (98.2, "°F")
        }
    }

    var body: some View {
        let rows = exampleRows
        let moreCount = max(0, selectedMetricCount - rows.count)

        VStack(alignment: .leading, spacing: 8) {
            CSVGridView(header: Self.header, rows: rows)
                .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: rows.map(\.id))

            if rows.isEmpty {
                Text("Turn on a metric to add rows.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if moreCount > 0 {
                Text("+ \(moreCount) more \(moreCount == 1 ? "metric" : "metrics")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example rows")
        .accessibilityValue(accessibilitySummary(rows: rows, moreCount: moreCount))
        .accessibilityIdentifier("csvPreview")
    }

    private func accessibilitySummary(rows: [CSVGridView.Row], moreCount: Int) -> String {
        let columns = "Columns: " + Self.header.joined(separator: ", ") + "."
        guard !rows.isEmpty else {
            return columns + " No metrics selected."
        }
        let names = rows.map { $0.cells[1] }.joined(separator: ", ")
        var summary = columns + " One made-up row each for " + names + "."
        if moreCount > 0 {
            summary += " \(moreCount) more \(moreCount == 1 ? "metric" : "metrics") selected."
        }
        return summary
    }
}
