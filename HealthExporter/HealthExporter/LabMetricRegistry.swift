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
        case .lipid: return "Lipid panel"
        case .cbc: return "CBC"
        case .cmp: return "CMP / BMP"
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
        ),
        LabMetric(
            name: "WBC",
            loincCode: LOINCCode.whiteBloodCellCount,
            group: .cbc,
            valuePrecision: 2
        ),
        LabMetric(
            name: "RBC",
            loincCode: LOINCCode.redBloodCellCount,
            group: .cbc,
            valuePrecision: 2
        ),
        LabMetric(
            name: "Hemoglobin",
            loincCode: LOINCCode.hemoglobin,
            group: .cbc,
            valuePrecision: 1
        ),
        LabMetric(
            name: "Hematocrit",
            loincCode: LOINCCode.hematocrit,
            group: .cbc,
            valuePrecision: 1
        ),
        LabMetric(
            name: "Platelets",
            loincCode: LOINCCode.platelets,
            group: .cbc,
            valuePrecision: 0
        ),
        LabMetric(
            name: "MCV",
            loincCode: LOINCCode.meanCorpuscularVolume,
            group: .cbc,
            valuePrecision: 1
        ),
        LabMetric(
            name: "MCH",
            loincCode: LOINCCode.meanCorpuscularHemoglobin,
            group: .cbc,
            valuePrecision: 1
        ),
        LabMetric(
            name: "MCHC",
            loincCode: LOINCCode.meanCorpuscularHemoglobinConcentration,
            group: .cbc,
            valuePrecision: 1
        ),
        LabMetric(
            name: "RDW",
            loincCode: LOINCCode.redCellDistributionWidth,
            group: .cbc,
            valuePrecision: 1
        ),
        LabMetric(
            name: "Fasting Glucose",
            loincCode: LOINCCode.fastingGlucose,
            group: .cmp,
            valuePrecision: 0
        ),
        LabMetric(
            name: "BUN",
            loincCode: LOINCCode.bloodUreaNitrogen,
            group: .cmp,
            valuePrecision: 0
        ),
        LabMetric(
            name: "Creatinine",
            loincCode: LOINCCode.creatinine,
            group: .cmp,
            valuePrecision: 2
        ),
        LabMetric(
            name: "eGFR",
            loincCode: LOINCCode.estimatedGlomerularFiltrationRate,
            group: .cmp,
            valuePrecision: 0
        ),
        LabMetric(
            name: "Sodium",
            loincCode: LOINCCode.sodium,
            group: .cmp,
            valuePrecision: 0
        ),
        LabMetric(
            name: "Potassium",
            loincCode: LOINCCode.potassium,
            group: .cmp,
            valuePrecision: 1
        ),
        LabMetric(
            name: "Chloride",
            loincCode: LOINCCode.chloride,
            group: .cmp,
            valuePrecision: 0
        ),
        LabMetric(
            name: "CO2 / Bicarbonate",
            loincCode: LOINCCode.carbonDioxideBicarbonate,
            group: .cmp,
            valuePrecision: 0
        ),
        LabMetric(
            name: "Calcium",
            loincCode: LOINCCode.calcium,
            group: .cmp,
            valuePrecision: 1
        ),
        LabMetric(
            name: "Total Protein",
            loincCode: LOINCCode.totalProtein,
            group: .cmp,
            valuePrecision: 1
        ),
        LabMetric(
            name: "Albumin",
            loincCode: LOINCCode.albumin,
            group: .cmp,
            valuePrecision: 1
        ),
        LabMetric(
            name: "Bilirubin Total",
            loincCode: LOINCCode.bilirubinTotal,
            group: .cmp,
            valuePrecision: 1
        ),
        LabMetric(
            name: "ALT",
            loincCode: LOINCCode.alanineAminotransferase,
            group: .cmp,
            valuePrecision: 0
        ),
        LabMetric(
            name: "AST",
            loincCode: LOINCCode.aspartateAminotransferase,
            group: .cmp,
            valuePrecision: 0
        ),
        LabMetric(
            name: "Alkaline Phosphatase",
            loincCode: LOINCCode.alkalinePhosphatase,
            group: .cmp,
            valuePrecision: 0
        ),
        LabMetric(
            name: "TSH",
            loincCode: LOINCCode.thyroidStimulatingHormone,
            group: .thyroid,
            valuePrecision: 2
        ),
        LabMetric(
            name: "Free T4",
            loincCode: LOINCCode.freeT4,
            group: .thyroid,
            valuePrecision: 2
        ),
        LabMetric(
            name: "Free T3",
            loincCode: LOINCCode.freeT3,
            group: .thyroid,
            valuePrecision: 2
        ),
        LabMetric(
            name: "25-OH Vitamin D",
            loincCode: LOINCCode.vitaminD25Hydroxy,
            group: .other,
            valuePrecision: 0
        ),
        LabMetric(
            name: "Vitamin B12",
            loincCode: LOINCCode.vitaminB12,
            group: .other,
            valuePrecision: 0
        ),
        LabMetric(
            name: "Ferritin",
            loincCode: LOINCCode.ferritin,
            group: .other,
            valuePrecision: 0
        ),
        LabMetric(
            name: "Iron",
            loincCode: LOINCCode.iron,
            group: .other,
            valuePrecision: 0
        ),
        LabMetric(
            name: "TIBC",
            loincCode: LOINCCode.totalIronBindingCapacity,
            group: .other,
            valuePrecision: 0
        ),
        LabMetric(
            name: "hs-CRP",
            loincCode: LOINCCode.highSensitivityCRP,
            group: .other,
            valuePrecision: 2
        )
    ]

    static func metric(forLoincCode loincCode: String) -> LabMetric? {
        all.first { $0.loincCode == loincCode }
    }

    static func metrics(in panel: LabPanel) -> [LabMetric] {
        all.filter { $0.group == panel }
    }
}
