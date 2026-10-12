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
        case .yyyyMMddHHmmss: return "yyyy-MM-dd HH:mm:ss"
        case .iso8601: return "ISO8601 (UTC)"
        case .yyyySlashMMddHHmmss: return "yyyy/MM/dd HH:mm:ss"
        case .MMddyyyyHHmmss: return "MM/dd/yyyy HH:mm:ss"
        case .ddMMMyyyyHHmmss: return "dd MMM yyyy HH:mm:ss"
        }
    }

    var dateFormat: String {
        switch self {
        case .yyyyMMddHHmmss: return "yyyy-MM-dd HH:mm:ss"
        case .iso8601: return "yyyy-MM-dd'T'HH:mm:ss'Z'"
        case .yyyySlashMMddHHmmss: return "yyyy/MM/dd HH:mm:ss"
        case .MMddyyyyHHmmss: return "MM/dd/yyyy HH:mm:ss"
        case .ddMMMyyyyHHmmss: return "dd MMM yyyy HH:mm:ss"
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

    @ObservationIgnored private let defaults: UserDefaults

    /// The lab panels and the labs selected one by one, with the selection rules.
    var labSelection: LabSelection {
        get { LabSelection(panels: selectedLabPanels, favoriteCodes: favoriteLabCodes) }
        set {
            if newValue.panels != selectedLabPanels { selectedLabPanels = newValue.panels }
            if newValue.favoriteCodes != favoriteLabCodes { favoriteLabCodes = newValue.favoriteCodes }
        }
    }

    /// One-time migration from the legacy boolean `exportA1C` setting to the
    /// new panels-and-favorites model. If `exportA1C == true` and the user
    /// has not yet customized `favoriteLabCodes`, seed Hemoglobin A1C in the
    /// favorites set so the toggle's user intent carries forward.
    static func migrateLegacyA1CSetting(in defaults: UserDefaults) {
        guard defaults.object(forKey: Key.favoriteLabCodes) == nil else { return }
        guard defaults.bool(forKey: Key.legacyExportA1C) else { return }
        defaults.set([LOINCCode.hemoglobinA1C], forKey: Key.favoriteLabCodes)
    }

    /// Reads every setting from `defaults`. Tests pass a suite of their own.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.migrateLegacyA1CSetting(in: defaults)

        let tempUnitRaw = defaults.string(forKey: Key.temperatureUnit) ?? TemperatureUnit.fahrenheit.rawValue
        self.temperatureUnit = TemperatureUnit(rawValue: tempUnitRaw) ?? .fahrenheit

        let weightUnitRaw = defaults.string(forKey: Key.weightUnit) ?? WeightUnit.pounds.rawValue
        self.weightUnit = WeightUnit(rawValue: weightUnitRaw) ?? .pounds

        let dateFormatRaw = defaults.string(forKey: Key.dateFormat) ?? DateFormatOption.yyyyMMddHHmmss.rawValue
        self.dateFormat = DateFormatOption(rawValue: dateFormatRaw) ?? .yyyyMMddHHmmss

        let sortOrderRaw = defaults.string(forKey: Key.sortOrder) ?? SortOrder.ascending.rawValue
        self.sortOrder = SortOrder(rawValue: sortOrderRaw) ?? .ascending

        self.autoDismissSaveConfirmation = defaults.object(forKey: Key.autoDismissSaveConfirmation) as? Bool ?? true

        // Load metric preferences (default to exporting weight and steps)
        self.exportWeight = defaults.object(forKey: Key.exportWeight) as? Bool ?? true
        self.exportSteps = defaults.object(forKey: Key.exportSteps) as? Bool ?? true
        self.exportGlucose = defaults.object(forKey: Key.exportGlucose) as? Bool ?? false

        let panelsRaw = defaults.array(forKey: Key.selectedLabPanels) as? [String] ?? []
        self.selectedLabPanels = Set(panelsRaw.compactMap(LabPanel.init(rawValue:)))

        let favoritesRaw = defaults.array(forKey: Key.favoriteLabCodes) as? [String] ?? []
        self.favoriteLabCodes = Set(favoritesRaw)

        let vitalsRaw = defaults.array(forKey: Key.selectedVitalMetrics) as? [String] ?? []
        self.selectedVitalMetrics = Set(vitalsRaw.compactMap(VitalMetric.init(rawValue:)))

        let expandedPanelsRaw = defaults.array(forKey: Key.expandedLabPanels) as? [String] ?? []
        self.expandedLabPanels = Set(expandedPanelsRaw.compactMap(LabPanel.init(rawValue:)))

        self.expandedVitalsSection = defaults.object(forKey: Key.expandedVitalsSection) as? Bool ?? false

        self.lastXDaysValue = defaults.object(forKey: Key.lastXDaysValue) as? Int ?? 30
        self.lastXRecordsValue = defaults.object(forKey: Key.lastXRecordsValue) as? Int ?? 100
        // Assignments in init do not run `didSet`, so loading writes nothing back.
    }
}
