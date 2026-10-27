import Foundation
import Observation

nonisolated enum DateFormatOption: String, CaseIterable {
    case yyyyMMddHHmmss = "yyyy-MM-dd HH:mm:ss"
    case iso8601 = "ISO8601"
    case yyyySlashMMddHHmmss = "yyyy/MM/dd HH:mm:ss"
    case MMddyyyyHHmmss = "MM/dd/yyyy HH:mm:ss"
    case ddMMMyyyyHHmmss = "dd MMM yyyy HH:mm:ss"

    var displayName: String {
        switch self {
        case .yyyyMMddHHmmss: "yyyy-MM-dd HH:mm:ss"
        case .iso8601: "ISO8601 (UTC)"
        case .yyyySlashMMddHHmmss: "yyyy/MM/dd HH:mm:ss"
        case .MMddyyyyHHmmss: "MM/dd/yyyy HH:mm:ss"
        case .ddMMMyyyyHHmmss: "dd MMM yyyy HH:mm:ss"
        }
    }

    var dateFormat: String {
        switch self {
        case .yyyyMMddHHmmss: "yyyy-MM-dd HH:mm:ss"
        case .iso8601: "yyyy-MM-dd'T'HH:mm:ss'Z'"
        case .yyyySlashMMddHHmmss: "yyyy/MM/dd HH:mm:ss"
        case .MMddyyyyHHmmss: "MM/dd/yyyy HH:mm:ss"
        case .ddMMMyyyyHHmmss: "dd MMM yyyy HH:mm:ss"
        }
    }

    var isUTC: Bool {
        self == .iso8601
    }
}

nonisolated enum SortOrder: String, CaseIterable {
    case ascending = "Oldest → Newest"
    case descending = "Newest → Oldest"
}

nonisolated enum TemperatureUnit: String, CaseIterable {
    case celsius = "Celsius (°C)"
    case fahrenheit = "Fahrenheit (°F)"
}

nonisolated enum WeightUnit: String, CaseIterable {
    case kilograms = "Kilograms (kg)"
    case pounds = "Pounds (lbs)"
}

/// The user's settings. Each property writes its value to `UserDefaults`
/// when it changes. The keys and value formats are the ones every earlier
/// version used, so existing users keep their settings.
@Observable
final class SettingsManager {
    /// The `UserDefaults` keys. Never rename one: it would reset that setting.
    enum Key {
        static let temperatureUnit = "temperatureUnit"
        static let weightUnit = "weightUnit"
        static let dateFormat = "dateFormat"
        static let sortOrder = "sortOrder"
        static let autoDismissSaveConfirmation = "autoDismissSaveConfirmation"
        static let exportWeight = "exportWeight"
        static let exportSteps = "exportSteps"
        static let exportGlucose = "exportGlucose"
        static let selectedLabPanels = "selectedLabPanels"
        static let favoriteLabCodes = "favoriteLabCodes"
        static let selectedVitalMetrics = "selectedVitalMetrics"
        static let expandedLabPanels = "expandedLabPanels"
        static let expandedVitalsSection = "expandedVitalsSection"
        static let lastXDaysValue = "lastXDaysValue"
        static let lastXRecordsValue = "lastXRecordsValue"
        /// The "Keep Export History" switch, a Bool.
        static let keepExportHistory = "keepExportHistory"
        /// `ExportHistory` as JSON `Data`.
        static let exportHistory = "exportHistory"
        /// The boolean A1C setting from before lab panels. Read once, by the migration.
        static let legacyExportA1C = "exportA1C"
    }

    var temperatureUnit: TemperatureUnit {
        didSet { defaults.set(temperatureUnit.rawValue, forKey: Key.temperatureUnit) }
    }

    var weightUnit: WeightUnit {
        didSet { defaults.set(weightUnit.rawValue, forKey: Key.weightUnit) }
    }

    var autoDismissSaveConfirmation: Bool {
        didSet { defaults.set(autoDismissSaveConfirmation, forKey: Key.autoDismissSaveConfirmation) }
    }

    var exportWeight: Bool {
        didSet { defaults.set(exportWeight, forKey: Key.exportWeight) }
    }

    var exportSteps: Bool {
        didSet { defaults.set(exportSteps, forKey: Key.exportSteps) }
    }

    var exportGlucose: Bool {
        didSet { defaults.set(exportGlucose, forKey: Key.exportGlucose) }
    }

    var selectedLabPanels: Set<LabPanel> {
        didSet { defaults.set(selectedLabPanels.map(\.rawValue), forKey: Key.selectedLabPanels) }
    }

    var favoriteLabCodes: Set<String> {
        didSet { defaults.set(Array(favoriteLabCodes), forKey: Key.favoriteLabCodes) }
    }

    var selectedVitalMetrics: Set<VitalMetric> {
        didSet { defaults.set(selectedVitalMetrics.map(\.rawValue), forKey: Key.selectedVitalMetrics) }
    }

    var expandedLabPanels: Set<LabPanel> {
        didSet { defaults.set(expandedLabPanels.map(\.rawValue), forKey: Key.expandedLabPanels) }
    }

    var expandedVitalsSection: Bool {
        didSet { defaults.set(expandedVitalsSection, forKey: Key.expandedVitalsSection) }
    }

    var dateFormat: DateFormatOption {
        didSet { defaults.set(dateFormat.rawValue, forKey: Key.dateFormat) }
    }

    var sortOrder: SortOrder {
        didSet { defaults.set(sortOrder.rawValue, forKey: Key.sortOrder) }
    }

    var lastXDaysValue: Int {
        didSet { defaults.set(lastXDaysValue, forKey: Key.lastXDaysValue) }
    }

    var lastXRecordsValue: Int {
        didSet { defaults.set(lastXRecordsValue, forKey: Key.lastXRecordsValue) }
    }

    /// When the user turns it off, the history is cleared.
    var keepExportHistory: Bool {
        didSet {
            defaults.set(keepExportHistory, forKey: Key.keepExportHistory)
            if !keepExportHistory {
                clearExportHistory()
            }
        }
    }

    /// The last exports, newest first. An empty history removes the key.
    var exportHistory: ExportHistory {
        didSet {
            if exportHistory.isEmpty {
                defaults.removeObject(forKey: Key.exportHistory)
            } else if let data = exportHistory.encoded() {
                defaults.set(data, forKey: Key.exportHistory)
            }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// The lab panels and the labs selected one by one, with the selection rules.
    var labSelection: LabSelection {
        get { LabSelection(panels: selectedLabPanels, favoriteCodes: favoriteLabCodes) }
        set {
            if newValue.panels != selectedLabPanels {
                selectedLabPanels = newValue.panels
            }
            if newValue.favoriteCodes != favoriteLabCodes {
                favoriteLabCodes = newValue.favoriteCodes
            }
        }
    }

    /// Adds a saved export to the history, unless the user turned it off.
    func recordExport(_ entry: ExportHistoryEntry) {
        guard keepExportHistory else { return }
        exportHistory.add(entry)
    }

    /// Removes every entry, and the stored value too, even one that did not decode.
    func clearExportHistory() {
        exportHistory.clear()
    }

    /// Export Again: sets the selection of Choose Data to the selection of
    /// `entry`. A lab, panel or vital that this version does not know is
    /// skipped. Sets the days or the records value when the entry used one.
    /// Returns the date range, which Choose Data takes as its initial value.
    @discardableResult
    func restoreSelection(from entry: ExportHistoryEntry) -> ExportHistoryDateRange {
        exportWeight = entry.exportWeight
        exportSteps = entry.exportSteps
        exportGlucose = entry.exportGlucose
        selectedVitalMetrics = Set(entry.knownVitalMetrics)
        labSelection = LabSelection(
            panels: Set(entry.knownLabPanels),
            favoriteCodes: Set(entry.knownLabMetrics.map(\.loincCode))
        )
        switch entry.dateRange {
        case let .lastDays(days):
            lastXDaysValue = days
        case let .lastRecords(records):
            lastXRecordsValue = records
        case .specific, .allRecords:
            break
        }
        return entry.dateRange
    }

    /// One-time migration from the legacy boolean `exportA1C` setting to the
    /// new panels-and-favorites model. If `exportA1C == true` and the user
    /// has not yet customized `favoriteLabCodes`, seed Hemoglobin A1C in the
    /// favorites set so the toggle's user intent carries forward.
    static func migrateLegacyA1CSetting(in defaults: UserDefaults) {
        guard defaults.object(forKey: Key.favoriteLabCodes) == nil, defaults.bool(forKey: Key.legacyExportA1C) else { return }
        defaults.set([LOINCCode.hemoglobinA1C], forKey: Key.favoriteLabCodes)
    }

    /// Reads every setting from `defaults`. Tests pass a suite of their own.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.migrateLegacyA1CSetting(in: defaults)

        let tempUnitRaw = defaults.string(forKey: Key.temperatureUnit) ?? TemperatureUnit.fahrenheit.rawValue
        temperatureUnit = TemperatureUnit(rawValue: tempUnitRaw) ?? .fahrenheit

        let weightUnitRaw = defaults.string(forKey: Key.weightUnit) ?? WeightUnit.pounds.rawValue
        weightUnit = WeightUnit(rawValue: weightUnitRaw) ?? .pounds

        let dateFormatRaw = defaults.string(forKey: Key.dateFormat) ?? DateFormatOption.yyyyMMddHHmmss.rawValue
        dateFormat = DateFormatOption(rawValue: dateFormatRaw) ?? .yyyyMMddHHmmss

        let sortOrderRaw = defaults.string(forKey: Key.sortOrder) ?? SortOrder.ascending.rawValue
        sortOrder = SortOrder(rawValue: sortOrderRaw) ?? .ascending

        autoDismissSaveConfirmation = defaults.object(forKey: Key.autoDismissSaveConfirmation) as? Bool ?? true

        // Load metric preferences (default to exporting weight and steps)
        exportWeight = defaults.object(forKey: Key.exportWeight) as? Bool ?? true
        exportSteps = defaults.object(forKey: Key.exportSteps) as? Bool ?? true
        exportGlucose = defaults.object(forKey: Key.exportGlucose) as? Bool ?? false

        let panelsRaw = defaults.array(forKey: Key.selectedLabPanels) as? [String] ?? []
        selectedLabPanels = Set(panelsRaw.compactMap(LabPanel.init(rawValue:)))

        let favoritesRaw = defaults.array(forKey: Key.favoriteLabCodes) as? [String] ?? []
        favoriteLabCodes = Set(favoritesRaw)

        let vitalsRaw = defaults.array(forKey: Key.selectedVitalMetrics) as? [String] ?? []
        selectedVitalMetrics = Set(vitalsRaw.compactMap(VitalMetric.init(rawValue:)))

        let expandedPanelsRaw = defaults.array(forKey: Key.expandedLabPanels) as? [String] ?? []
        expandedLabPanels = Set(expandedPanelsRaw.compactMap(LabPanel.init(rawValue:)))

        expandedVitalsSection = defaults.object(forKey: Key.expandedVitalsSection) as? Bool ?? false

        lastXDaysValue = defaults.object(forKey: Key.lastXDaysValue) as? Int ?? 30
        lastXRecordsValue = defaults.object(forKey: Key.lastXRecordsValue) as? Int ?? 100

        keepExportHistory = defaults.object(forKey: Key.keepExportHistory) as? Bool ?? true
        exportHistory = ExportHistory.decoded(from: defaults.data(forKey: Key.exportHistory))
        // Assignments in init do not run `didSet`, so loading writes nothing back.
    }
}
