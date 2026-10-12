import Foundation
@testable import HealthExporter
import Testing

struct SettingsEnumTests {
    // MARK: - DateFormatOption

    @Test func dateFormatOption_allCasesCount() {
        #expect(DateFormatOption.allCases.count == 5)
    }

    @Test func dateFormatOption_rawValues() {
        #expect(DateFormatOption.yyyyMMddHHmmss.rawValue == "yyyy-MM-dd HH:mm:ss")
        #expect(DateFormatOption.iso8601.rawValue == "ISO8601")
        #expect(DateFormatOption.yyyySlashMMddHHmmss.rawValue == "yyyy/MM/dd HH:mm:ss")
        #expect(DateFormatOption.MMddyyyyHHmmss.rawValue == "MM/dd/yyyy HH:mm:ss")
        #expect(DateFormatOption.ddMMMyyyyHHmmss.rawValue == "dd MMM yyyy HH:mm:ss")
    }

    @Test func dateFormatOption_displayNames() {
        #expect(DateFormatOption.yyyyMMddHHmmss.displayName == "yyyy-MM-dd HH:mm:ss")
        #expect(DateFormatOption.iso8601.displayName == "ISO8601 (UTC)")
        #expect(DateFormatOption.yyyySlashMMddHHmmss.displayName == "yyyy/MM/dd HH:mm:ss")
        #expect(DateFormatOption.MMddyyyyHHmmss.displayName == "MM/dd/yyyy HH:mm:ss")
        #expect(DateFormatOption.ddMMMyyyyHHmmss.displayName == "dd MMM yyyy HH:mm:ss")
    }

    @Test func dateFormatOption_dateFormats() {
        #expect(DateFormatOption.yyyyMMddHHmmss.dateFormat == "yyyy-MM-dd HH:mm:ss")
        #expect(DateFormatOption.iso8601.dateFormat == "yyyy-MM-dd'T'HH:mm:ss'Z'")
        #expect(DateFormatOption.yyyySlashMMddHHmmss.dateFormat == "yyyy/MM/dd HH:mm:ss")
        #expect(DateFormatOption.MMddyyyyHHmmss.dateFormat == "MM/dd/yyyy HH:mm:ss")
        #expect(DateFormatOption.ddMMMyyyyHHmmss.dateFormat == "dd MMM yyyy HH:mm:ss")
    }

    @Test func dateFormatOption_isUTC_onlyISO8601() {
        #expect(DateFormatOption.iso8601.isUTC)
        for option in DateFormatOption.allCases where option != .iso8601 {
            #expect(!option.isUTC, "\(option) should not be UTC")
        }
    }

    @Test func dateFormatOption_initFromRawValue() {
        #expect(DateFormatOption(rawValue: "ISO8601") == .iso8601)
        #expect(DateFormatOption(rawValue: "invalid") == nil)
    }

    // MARK: - SortOrder

    @Test func sortOrder_allCasesCount() {
        #expect(SortOrder.allCases.count == 2)
    }

    @Test func sortOrder_rawValues() {
        #expect(SortOrder.ascending.rawValue == "Oldest → Newest")
        #expect(SortOrder.descending.rawValue == "Newest → Oldest")
    }

    @Test func sortOrder_initFromRawValue() {
        #expect(SortOrder(rawValue: "Oldest → Newest") == .ascending)
        #expect(SortOrder(rawValue: "Newest → Oldest") == .descending)
        #expect(SortOrder(rawValue: "invalid") == nil)
    }

    // MARK: - TemperatureUnit

    @Test func temperatureUnit_allCasesCount() {
        #expect(TemperatureUnit.allCases.count == 2)
    }

    @Test func temperatureUnit_rawValues() {
        #expect(TemperatureUnit.celsius.rawValue == "Celsius (°C)")
        #expect(TemperatureUnit.fahrenheit.rawValue == "Fahrenheit (°F)")
    }

    @Test func temperatureUnit_initFromRawValue() {
        #expect(TemperatureUnit(rawValue: "Celsius (°C)") == .celsius)
        #expect(TemperatureUnit(rawValue: "Fahrenheit (°F)") == .fahrenheit)
        #expect(TemperatureUnit(rawValue: "invalid") == nil)
    }

    // MARK: - WeightUnit

    @Test func weightUnit_allCasesCount() {
        #expect(WeightUnit.allCases.count == 2)
    }

    @Test func weightUnit_rawValues() {
        #expect(WeightUnit.kilograms.rawValue == "Kilograms (kg)")
        #expect(WeightUnit.pounds.rawValue == "Pounds (lbs)")
    }

    @Test func weightUnit_initFromRawValue() {
        #expect(WeightUnit(rawValue: "Kilograms (kg)") == .kilograms)
        #expect(WeightUnit(rawValue: "Pounds (lbs)") == .pounds)
        #expect(WeightUnit(rawValue: "invalid") == nil)
    }
}
