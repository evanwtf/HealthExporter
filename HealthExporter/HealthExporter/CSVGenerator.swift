import HealthKit

nonisolated struct ExportPreviewEstimate: Sendable {
    static let confirmationRowThreshold = 500
    static let confirmationByteThreshold = 1_000_000

    let rowCount: Int
    let estimatedByteCount: Int

    var roundedRowCount: Int {
        Self.roundedRowCount(for: rowCount)
    }

    var formattedRowCount: String {
        roundedRowCount.formatted()
    }

    var formattedByteCount: String {
        ByteCountFormatter.string(fromByteCount: Int64(estimatedByteCount), countStyle: .file)
    }

    var summaryText: String {
        "This will export around \(formattedRowCount) rows (\(formattedByteCount))."
    }

    var shouldShowConfirmation: Bool {
        rowCount > Self.confirmationRowThreshold || estimatedByteCount > Self.confirmationByteThreshold
    }

    static func roundedRowCount(for count: Int) -> Int {
        guard count > 0 else { return 0 }

        if count < 1_000 {
            return max(100, ((count + 50) / 100) * 100)
        }

        return ((count + 500) / 1_000) * 1_000
    }
}

nonisolated enum CSVGenerator {

    /// Three-line disclaimer prepended to every export. Each line begins with `### `
    /// so common CSV parsers can be configured to treat them as comments.
    static let csvDisclaimer = """
        ### HealthExporterCSV: data exported as-is from Apple Health.
        ### No warranty of accuracy, completeness, or fitness for any purpose.
        ### Not a medical record. Verify with your healthcare provider before any clinical use.
        """

    static let csvHeader = "Date,Metric,LOINC,Value,Unit,Source,Meal Time"

    /// Disclaimer block followed by a newline, then the column header and a newline.
    /// Use this as the starting buffer for every CSV export.
    static let csvPreamble = csvDisclaimer + "\n" + csvHeader + "\n"

    /// Fixed POSIX locale and Gregorian calendar, so a device set to another
    /// calendar (for example Buddhist) still writes a Gregorian year.
    static func makeDateFormatter(for option: DateFormatOption) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = option.dateFormat
        if option.isUTC {
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
        }
        return formatter
    }

    /// Wraps a value in double quotes if it contains a comma, quote, CR or LF (RFC 4180).
    static func csvEscape(_ field: String) -> String {
        if field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" || $0 == "\r\n" }) {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    static func mealTimeLabel(_ mealTime: HKBloodGlucoseMealTime?) -> String {
        switch mealTime {
        case .preprandial: return "Before Meal"
        case .postprandial: return "After Meal"
        default: return ""
        }
    }

    private static func weightRow(for sample: HKQuantitySample, unit: WeightUnit, dateFormatter: DateFormatter) -> String {
        let date = dateFormatter.string(from: sample.startDate)
        let weightKg = sample.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
        let (value, unitString) = convertWeight(weightKg, to: unit)
        let source = csvEscape(sample.sourceRevision.source.name)
        return "\(date),Weight,,\(String(format: "%.2f", value)),\(unitString),\(source),\n"
    }

    private static func stepsRow(for sample: HKQuantitySample, dateFormatter: DateFormatter) -> String {
        let date = dateFormatter.string(from: sample.startDate)
        let steps = sample.quantity.doubleValue(for: HKUnit.count())
        let source = csvEscape(sample.sourceRevision.source.name)
        return "\(date),Steps,,\(Int(steps.rounded())),steps,\(source),\n"
    }

    private static func glucoseRow(for sample: GlucoseSampleMgDl, dateFormatter: DateFormatter) -> String {
        let date = dateFormatter.string(from: sample.startDate)
        let source = csvEscape(sample.source)
        let mealTime = mealTimeLabel(sample.mealTime)
        return "\(date),Blood Glucose,,\(String(format: "%.0f", sample.value)),mg/dL,\(source),\(mealTime)\n"
    }

    private static func labResultRow(for sample: LabResultSample, dateFormatter: DateFormatter) -> String {
        let date = dateFormatter.string(from: sample.effectiveDateTime)
        let metric = csvEscape(sample.metricName)
        let loinc = csvEscape(sample.loincCode)
        let unit = csvEscape(sample.unit)
        let source = csvEscape(sample.source)
        let precision = LabMetricRegistry.metric(forLoincCode: sample.loincCode)?.valuePrecision ?? 2
        let value = (sample.comparator ?? "") + String(format: "%.\(precision)f", sample.value)
        return "\(date),\(metric),\(loinc),\(value),\(unit),\(source),\n"
    }

    private static func vitalRow(for sample: HKQuantitySample, component: VitalMetricComponent, temperatureUnit: TemperatureUnit, dateFormatter: DateFormatter) -> String {
        let date = dateFormatter.string(from: sample.startDate)
        let source = csvEscape(sample.sourceRevision.source.name)
        let result = component.valueAndUnit(from: sample.quantity, temperatureUnit: temperatureUnit)
        let value = String(format: "%.\(component.valuePrecision)f", result.value)
        let metric = csvEscape(component.displayName)
        let unit = csvEscape(result.unit)
        return "\(date),\(metric),,\(value),\(unit),\(source),\n"
    }

    // MARK: - Append methods (memory-efficient, sort in-place, write directly to string)

    static func appendWeightRows(to csv: inout String, samples: inout [HKQuantitySample], unit: WeightUnit, dateFormat: DateFormatOption = .yyyyMMddHHmmss, sortOrder: SortOrder = .ascending) {
        let dateFormatter = makeDateFormatter(for: dateFormat)
        samples.sort { sortOrder == .ascending ? $0.startDate < $1.startDate : $0.startDate > $1.startDate }
        for sample in samples {
            csv.append(weightRow(for: sample, unit: unit, dateFormatter: dateFormatter))
        }
    }

    static func appendStepsRows(to csv: inout String, samples: inout [HKQuantitySample], dateFormat: DateFormatOption = .yyyyMMddHHmmss, sortOrder: SortOrder = .ascending) {
        let dateFormatter = makeDateFormatter(for: dateFormat)
        samples.sort { sortOrder == .ascending ? $0.startDate < $1.startDate : $0.startDate > $1.startDate }
        for sample in samples {
            csv.append(stepsRow(for: sample, dateFormatter: dateFormatter))
        }
    }

    static func appendGlucoseRows(to csv: inout String, samples: inout [GlucoseSampleMgDl], dateFormat: DateFormatOption = .yyyyMMddHHmmss, sortOrder: SortOrder = .ascending) {
        let dateFormatter = makeDateFormatter(for: dateFormat)
        samples.sort { sortOrder == .ascending ? $0.startDate < $1.startDate : $0.startDate > $1.startDate }
        for sample in samples {
            csv.append(glucoseRow(for: sample, dateFormatter: dateFormatter))
        }
    }

    static func appendLabResultRows(to csv: inout String, samples: inout [LabResultSample], dateFormat: DateFormatOption = .yyyyMMddHHmmss, sortOrder: SortOrder = .ascending) {
        let dateFormatter = makeDateFormatter(for: dateFormat)
        samples.sort { sortOrder == .ascending ? $0.effectiveDateTime < $1.effectiveDateTime : $0.effectiveDateTime > $1.effectiveDateTime }
        for sample in samples {
            csv.append(labResultRow(for: sample, dateFormatter: dateFormatter))
        }
    }

    static func appendVitalRows(to csv: inout String, samplesByComponent: inout [VitalMetricComponent: [HKQuantitySample]], temperatureUnit: TemperatureUnit, dateFormat: DateFormatOption = .yyyyMMddHHmmss, sortOrder: SortOrder = .ascending) {
        let dateFormatter = makeDateFormatter(for: dateFormat)
        for component in VitalMetricComponent.allCases {
            guard var samples = samplesByComponent[component] else { continue }
            samplesByComponent[component] = nil
            samples.sort { sortOrder == .ascending ? $0.startDate < $1.startDate : $0.startDate > $1.startDate }
            for sample in samples {
                csv.append(vitalRow(for: sample, component: component, temperatureUnit: temperatureUnit, dateFormatter: dateFormatter))
            }
        }
    }

    static func makePreviewEstimate(weightSamples: [HKQuantitySample]?, stepsSamples: [HKQuantitySample]?, glucoseSamples: [GlucoseSampleMgDl]?, labResults: [LabResultSample]?, vitalSamples: [VitalMetricComponent: [HKQuantitySample]]? = nil, weightUnit: WeightUnit, temperatureUnit: TemperatureUnit = .fahrenheit, dateFormat: DateFormatOption = .yyyyMMddHHmmss) -> ExportPreviewEstimate {
        let weightCount = weightSamples?.count ?? 0
        let stepsCount = stepsSamples?.count ?? 0
        let glucoseCount = glucoseSamples?.count ?? 0
        let labCount = labResults?.count ?? 0
        let vitalCount = vitalSamples?.values.reduce(0) { $0 + $1.count } ?? 0
        let rowCount = weightCount + stepsCount + glucoseCount + labCount + vitalCount

        let dateFormatter = makeDateFormatter(for: dateFormat)
        var estimatedByteCount = csvPreamble.utf8.count

        if let samples = weightSamples {
            for sample in samples {
                estimatedByteCount += weightRow(for: sample, unit: weightUnit, dateFormatter: dateFormatter).utf8.count
            }
        }

        if let samples = stepsSamples {
            for sample in samples {
                estimatedByteCount += stepsRow(for: sample, dateFormatter: dateFormatter).utf8.count
            }
        }

        if let samples = glucoseSamples {
            for sample in samples {
                estimatedByteCount += glucoseRow(for: sample, dateFormatter: dateFormatter).utf8.count
            }
        }

        if let samples = labResults {
            for sample in samples {
                estimatedByteCount += labResultRow(for: sample, dateFormatter: dateFormatter).utf8.count
            }
        }

        if let samplesByComponent = vitalSamples {
            for component in VitalMetricComponent.allCases {
                guard let samples = samplesByComponent[component] else { continue }
                for sample in samples {
                    estimatedByteCount += vitalRow(for: sample, component: component, temperatureUnit: temperatureUnit, dateFormatter: dateFormatter).utf8.count
                }
            }
        }

        return ExportPreviewEstimate(rowCount: rowCount, estimatedByteCount: estimatedByteCount)
    }

    // MARK: - Legacy convenience methods (used by tests and single-metric exports)

    static func generateWeightCSV(from samples: [HKQuantitySample], unit: WeightUnit, dateFormat: DateFormatOption = .yyyyMMddHHmmss, sortOrder: SortOrder = .ascending) -> String {
        var csv = csvPreamble
        var mutableSamples = samples
        appendWeightRows(to: &csv, samples: &mutableSamples, unit: unit, dateFormat: dateFormat, sortOrder: sortOrder)
        return csv
    }

    static func generateStepsCSV(from samples: [HKQuantitySample], dateFormat: DateFormatOption = .yyyyMMddHHmmss, sortOrder: SortOrder = .ascending) -> String {
        var csv = csvPreamble
        var mutableSamples = samples
        appendStepsRows(to: &csv, samples: &mutableSamples, dateFormat: dateFormat, sortOrder: sortOrder)
        return csv
    }

    /// Builds the full export. Each array is set to nil (or emptied) as soon as
    /// its rows are written, so the caller's copy is released while later
    /// sections are still being generated.
    static func generateCombinedCSV(
        weightSamples: inout [HKQuantitySample]?,
        stepsSamples: inout [HKQuantitySample]?,
        glucoseSamples: inout [GlucoseSampleMgDl]?,
        labResults: inout [LabResultSample]?,
        vitalSamples: inout [VitalMetricComponent: [HKQuantitySample]],
        weightUnit: WeightUnit,
        temperatureUnit: TemperatureUnit = .fahrenheit,
        dateFormat: DateFormatOption = .yyyyMMddHHmmss,
        sortOrder: SortOrder = .ascending
    ) -> String {
        var csv = csvPreamble

        if var samples = weightSamples {
            weightSamples = nil
            appendWeightRows(to: &csv, samples: &samples, unit: weightUnit, dateFormat: dateFormat, sortOrder: sortOrder)
        }

        if var samples = stepsSamples {
            stepsSamples = nil
            appendStepsRows(to: &csv, samples: &samples, dateFormat: dateFormat, sortOrder: sortOrder)
        }

        if var samples = glucoseSamples {
            glucoseSamples = nil
            appendGlucoseRows(to: &csv, samples: &samples, dateFormat: dateFormat, sortOrder: sortOrder)
        }

        if var samples = labResults {
            labResults = nil
            appendLabResultRows(to: &csv, samples: &samples, dateFormat: dateFormat, sortOrder: sortOrder)
        }

        if !vitalSamples.isEmpty {
            appendVitalRows(to: &csv, samplesByComponent: &vitalSamples, temperatureUnit: temperatureUnit, dateFormat: dateFormat, sortOrder: sortOrder)
        }

        return csv
    }

    private static func convertWeight(_ weightKg: Double, to unit: WeightUnit) -> (Double, String) {
        switch unit {
        case .kilograms:
            return (weightKg, "kg")
        case .pounds:
            let weightLbs = weightKg * 2.2046226218
            return (weightLbs, "lbs")
        }
    }
}
