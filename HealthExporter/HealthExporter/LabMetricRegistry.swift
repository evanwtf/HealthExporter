import Foundation

/// Logical grouping of lab metrics surfaced as panel-level toggles in the UI.
enum LabPanel: String, CaseIterable, Codable {
    case lipid
    case cbc
    case cmp
    case thyroid
    case other

    var displayName: String {
        switch self {
        case .lipid: return "Lipid Panel"
        case .cbc: return "CBC"
        case .cmp: return "CMP"
        case .thyroid: return "Thyroid"
        case .other: return "Other"
        }
    }
}

/// Static description of a single lab observation supported for export.
/// `id == loincCode` so the registry is keyed by the LOINC code throughout.
struct LabMetric: Identifiable, Hashable {
    let name: String
    let loincCode: String
    let group: LabPanel
    let valuePrecision: Int

    var id: String { loincCode }
}

/// Centralized list of lab metrics the exporter knows how to render.
/// Add new entries here to expose them in the UI and CSV pipeline.
enum LabMetricRegistry {
    static let all: [LabMetric] = [
        LabMetric(
            name: "Hemoglobin A1C",
            loincCode: LOINCCode.hemoglobinA1C,
            group: .other,
            valuePrecision: 2
        ),
        LabMetric(
            name: "Total Cholesterol",
            loincCode: LOINCCode.totalCholesterol,
            group: .lipid,
            valuePrecision: 0
        ),
        LabMetric(
            name: "HDL Cholesterol",
            loincCode: LOINCCode.hdlCholesterol,
            group: .lipid,
            valuePrecision: 0
        ),
        LabMetric(
            name: "LDL Cholesterol",
            loincCode: LOINCCode.ldlCholesterolDirect,
            group: .lipid,
            valuePrecision: 0
        ),
        LabMetric(
            name: "Triglycerides",
            loincCode: LOINCCode.triglycerides,
            group: .lipid,
            valuePrecision: 0
        )
    ]

    static func metric(forLoincCode loincCode: String) -> LabMetric? {
        all.first { $0.loincCode == loincCode }
    }

    static func metrics(in panel: LabPanel) -> [LabMetric] {
        all.filter { $0.group == panel }
    }
}
