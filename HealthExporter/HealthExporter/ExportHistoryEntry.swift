import Foundation

/// One saved export: what the user selected, the date range, and the size of
/// the file. An entry holds no health value, and no file name or location.
///
/// The vitals, lab panels and lab codes are raw strings, so an entry still
/// decodes after a later version removes a case or a lab.
nonisolated struct ExportHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    /// When the user saved the file.
    var date: Date
    var exportWeight: Bool
    var exportSteps: Bool
    var exportGlucose: Bool
    /// `VitalMetric` raw values, in `VitalMetric.allCases` order.
    var vitalMetrics: [String]
    /// `LabPanel` raw values, in `LabPanel.allCases` order.
    var labPanels: [String]
    /// The primary LOINC codes of the labs selected on their own, in registry order.
    var labCodes: [String]
    var dateRange: ExportHistoryDateRange
    var rowCount: Int
    var byteCount: Int
    /// The names of the metrics that did not load, for example "Steps".
    var failedMetrics: [String]

    /// Builds an entry from the Choose Data selection and the built file.
    init(
        date: Date,
        exportWeight: Bool,
        exportSteps: Bool,
        exportGlucose: Bool,
        vitalMetrics: Set<VitalMetric>,
        labSelection: LabSelection,
        dateRange: ExportHistoryDateRange,
        file: CSVFile,
        failedMetrics: [String]
    ) {
        self.date = date
        self.exportWeight = exportWeight
        self.exportSteps = exportSteps
        self.exportGlucose = exportGlucose
        self.vitalMetrics = VitalMetric.allCases.filter(vitalMetrics.contains).map(\.rawValue)
        labPanels = LabPanel.allCases.filter(labSelection.panels.contains).map(\.rawValue)
        labCodes = LabMetricRegistry.all.map(\.loincCode).filter(labSelection.favoriteCodes.contains)
        self.dateRange = dateRange
        rowCount = file.rowCount
        byteCount = file.byteCount
        self.failedMetrics = failedMetrics
    }

    /// The vitals that this version of the app knows.
    var knownVitalMetrics: [VitalMetric] {
        vitalMetrics.compactMap(VitalMetric.init(rawValue:))
    }

    /// The lab panels that this version of the app knows.
    var knownLabPanels: [LabPanel] {
        labPanels.compactMap(LabPanel.init(rawValue:))
    }

    /// The labs selected on their own that are still in `LabMetricRegistry`.
    var knownLabMetrics: [LabMetric] {
        labCodes.compactMap { code in
            LabMetricRegistry.all.first { $0.loincCode == code }
        }
    }

    /// The labs selected on their own whose panel is not selected too, so a
    /// summary does not name a lab twice.
    var labMetricsOutsideSelectedPanels: [LabMetric] {
        let panels = Set(knownLabPanels)
        return knownLabMetrics.filter { !panels.contains($0.group) }
    }

    var size: ExportSize {
        ExportSize(rowCount: rowCount, byteCount: byteCount)
    }

    /// For example "1,234 rows, 56 KB".
    var sizeText: String {
        "\(size.formattedRowCount) \(rowCount == 1 ? "row" : "rows"), \(size.formattedByteCount)"
    }
}
