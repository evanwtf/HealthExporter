import Foundation
import Combine

enum DateFormatOption: String, CaseIterable {
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

enum SortOrder: String, CaseIterable {
    case ascending = "Oldest → Newest"
    case descending = "Newest → Oldest"
}

enum TemperatureUnit: String, CaseIterable {
    case celsius = "Celsius (°C)"
    case fahrenheit = "Fahrenheit (°F)"
}

enum WeightUnit: String, CaseIterable {
    case kilograms = "Kilograms (kg)"
    case pounds = "Pounds (lbs)"
}

enum DistanceSpeedUnit: String, CaseIterable {
    case metric = "Metric (meters/kph)"
    case imperial = "Imperial (feet/mph)"
}

class SettingsManager: ObservableObject {
    @Published var temperatureUnit: TemperatureUnit
    @Published var weightUnit: WeightUnit
    @Published var distanceSpeedUnit: DistanceSpeedUnit
    @Published var autoDismissSaveConfirmation: Bool
    @Published var exportWeight: Bool
    @Published var exportSteps: Bool
    @Published var exportGlucose: Bool
    @Published var exportA1C: Bool
    @Published var selectedLabPanels: Set<LabPanel>
    @Published var favoriteLabCodes: Set<String>
    @Published var dateFormat: DateFormatOption
    @Published var sortOrder: SortOrder
    @Published var lastXDaysValue: Int
    @Published var lastXRecordsValue: Int

    private var cancellables = Set<AnyCancellable>()

    /// One-time migration from the legacy boolean `exportA1C` setting to the
    /// new panels-and-favorites model. If `exportA1C == true` and the user
    /// has not yet customized `favoriteLabCodes`, seed Hemoglobin A1C in the
    /// favorites set so the toggle's user intent carries forward.
    static func migrateLegacyA1CSetting(in defaults: UserDefaults) {
        guard defaults.object(forKey: "favoriteLabCodes") == nil else { return }
        guard defaults.bool(forKey: "exportA1C") else { return }
        defaults.set([LOINCCode.hemoglobinA1C], forKey: "favoriteLabCodes")
    }

    init() {
        Self.migrateLegacyA1CSetting(in: .standard)

        let tempUnitRaw = UserDefaults.standard.string(forKey: "temperatureUnit") ?? TemperatureUnit.fahrenheit.rawValue
        self.temperatureUnit = TemperatureUnit(rawValue: tempUnitRaw) ?? .fahrenheit

        let weightUnitRaw = UserDefaults.standard.string(forKey: "weightUnit") ?? WeightUnit.pounds.rawValue
        self.weightUnit = WeightUnit(rawValue: weightUnitRaw) ?? .pounds

        let distanceSpeedUnitRaw = UserDefaults.standard.string(forKey: "distanceSpeedUnit") ?? DistanceSpeedUnit.imperial.rawValue
        self.distanceSpeedUnit = DistanceSpeedUnit(rawValue: distanceSpeedUnitRaw) ?? .imperial

        let dateFormatRaw = UserDefaults.standard.string(forKey: "dateFormat") ?? DateFormatOption.yyyyMMddHHmmss.rawValue
        self.dateFormat = DateFormatOption(rawValue: dateFormatRaw) ?? .yyyyMMddHHmmss

        let sortOrderRaw = UserDefaults.standard.string(forKey: "sortOrder") ?? SortOrder.ascending.rawValue
        self.sortOrder = SortOrder(rawValue: sortOrderRaw) ?? .ascending

        self.autoDismissSaveConfirmation = UserDefaults.standard.object(forKey: "autoDismissSaveConfirmation") as? Bool ?? true

        // Load metric preferences (default to exporting weight and steps)
        self.exportWeight = UserDefaults.standard.object(forKey: "exportWeight") as? Bool ?? true
        self.exportSteps = UserDefaults.standard.object(forKey: "exportSteps") as? Bool ?? true
        self.exportGlucose = UserDefaults.standard.object(forKey: "exportGlucose") as? Bool ?? false

        self.exportA1C = UserDefaults.standard.object(forKey: "exportA1C") as? Bool ?? false

        let panelsRaw = UserDefaults.standard.array(forKey: "selectedLabPanels") as? [String] ?? []
        self.selectedLabPanels = Set(panelsRaw.compactMap(LabPanel.init(rawValue:)))

        let favoritesRaw = UserDefaults.standard.array(forKey: "favoriteLabCodes") as? [String] ?? []
        self.favoriteLabCodes = Set(favoritesRaw)

        self.lastXDaysValue = UserDefaults.standard.object(forKey: "lastXDaysValue") as? Int ?? 30
        self.lastXRecordsValue = UserDefaults.standard.object(forKey: "lastXRecordsValue") as? Int ?? 100

        // Persist changes via Combine subscribers (avoids @Published + didSet crash)
        $temperatureUnit
            .dropFirst()
            .sink { UserDefaults.standard.set($0.rawValue, forKey: "temperatureUnit") }
            .store(in: &cancellables)

        $weightUnit
            .dropFirst()
            .sink { UserDefaults.standard.set($0.rawValue, forKey: "weightUnit") }
            .store(in: &cancellables)

        $distanceSpeedUnit
            .dropFirst()
            .sink { UserDefaults.standard.set($0.rawValue, forKey: "distanceSpeedUnit") }
            .store(in: &cancellables)

        $dateFormat
            .dropFirst()
            .sink { UserDefaults.standard.set($0.rawValue, forKey: "dateFormat") }
            .store(in: &cancellables)

        $sortOrder
            .dropFirst()
            .sink { UserDefaults.standard.set($0.rawValue, forKey: "sortOrder") }
            .store(in: &cancellables)

        $autoDismissSaveConfirmation
            .dropFirst()
            .sink { UserDefaults.standard.set($0, forKey: "autoDismissSaveConfirmation") }
            .store(in: &cancellables)

        $exportWeight
            .dropFirst()
            .sink { UserDefaults.standard.set($0, forKey: "exportWeight") }
            .store(in: &cancellables)

        $exportSteps
            .dropFirst()
            .sink { UserDefaults.standard.set($0, forKey: "exportSteps") }
            .store(in: &cancellables)

        $exportGlucose
            .dropFirst()
            .sink { UserDefaults.standard.set($0, forKey: "exportGlucose") }
            .store(in: &cancellables)

        $exportA1C
            .dropFirst()
            .sink { UserDefaults.standard.set($0, forKey: "exportA1C") }
            .store(in: &cancellables)

        $selectedLabPanels
            .dropFirst()
            .sink { UserDefaults.standard.set($0.map(\.rawValue), forKey: "selectedLabPanels") }
            .store(in: &cancellables)

        $favoriteLabCodes
            .dropFirst()
            .sink { UserDefaults.standard.set(Array($0), forKey: "favoriteLabCodes") }
            .store(in: &cancellables)

        $lastXDaysValue
            .dropFirst()
            .sink { UserDefaults.standard.set($0, forKey: "lastXDaysValue") }
            .store(in: &cancellables)

        $lastXRecordsValue
            .dropFirst()
            .sink { UserDefaults.standard.set($0, forKey: "lastXRecordsValue") }
            .store(in: &cancellables)
    }
}
