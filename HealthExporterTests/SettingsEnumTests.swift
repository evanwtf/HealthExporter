import XCTest
@testable import HealthExporter

final class SettingsEnumTests: XCTestCase {

    // MARK: - DateFormatOption

    func testDateFormatOption_allCasesCount() {
        XCTAssertEqual(DateFormatOption.allCases.count, 5)
    }

    func testDateFormatOption_rawValues() {
        XCTAssertEqual(DateFormatOption.yyyyMMddHHmmss.rawValue, "yyyy-MM-dd HH:mm:ss")
        XCTAssertEqual(DateFormatOption.iso8601.rawValue, "ISO8601")
        XCTAssertEqual(DateFormatOption.yyyySlashMMddHHmmss.rawValue, "yyyy/MM/dd HH:mm:ss")
        XCTAssertEqual(DateFormatOption.MMddyyyyHHmmss.rawValue, "MM/dd/yyyy HH:mm:ss")
        XCTAssertEqual(DateFormatOption.ddMMMyyyyHHmmss.rawValue, "dd MMM yyyy HH:mm:ss")
    }

    func testDateFormatOption_displayNames() {
        XCTAssertEqual(DateFormatOption.yyyyMMddHHmmss.displayName, "yyyy-MM-dd HH:mm:ss")
        XCTAssertEqual(DateFormatOption.iso8601.displayName, "ISO8601 (UTC)")
        XCTAssertEqual(DateFormatOption.yyyySlashMMddHHmmss.displayName, "yyyy/MM/dd HH:mm:ss")
        XCTAssertEqual(DateFormatOption.MMddyyyyHHmmss.displayName, "MM/dd/yyyy HH:mm:ss")
        XCTAssertEqual(DateFormatOption.ddMMMyyyyHHmmss.displayName, "dd MMM yyyy HH:mm:ss")
    }

    func testDateFormatOption_dateFormats() {
        XCTAssertEqual(DateFormatOption.yyyyMMddHHmmss.dateFormat, "yyyy-MM-dd HH:mm:ss")
        XCTAssertEqual(DateFormatOption.iso8601.dateFormat, "yyyy-MM-dd'T'HH:mm:ss'Z'")
        XCTAssertEqual(DateFormatOption.yyyySlashMMddHHmmss.dateFormat, "yyyy/MM/dd HH:mm:ss")
        XCTAssertEqual(DateFormatOption.MMddyyyyHHmmss.dateFormat, "MM/dd/yyyy HH:mm:ss")
        XCTAssertEqual(DateFormatOption.ddMMMyyyyHHmmss.dateFormat, "dd MMM yyyy HH:mm:ss")
    }

    func testDateFormatOption_isUTC_onlyISO8601() {
        XCTAssertTrue(DateFormatOption.iso8601.isUTC)
        for option in DateFormatOption.allCases where option != .iso8601 {
            XCTAssertFalse(option.isUTC, "\(option) should not be UTC")
        }
    }

    func testDateFormatOption_initFromRawValue() {
        XCTAssertEqual(DateFormatOption(rawValue: "ISO8601"), .iso8601)
        XCTAssertNil(DateFormatOption(rawValue: "invalid"))
    }

    // MARK: - SortOrder

    func testSortOrder_allCasesCount() {
        XCTAssertEqual(SortOrder.allCases.count, 2)
    }

    func testSortOrder_rawValues() {
        XCTAssertEqual(SortOrder.ascending.rawValue, "Oldest → Newest")
        XCTAssertEqual(SortOrder.descending.rawValue, "Newest → Oldest")
    }

    func testSortOrder_initFromRawValue() {
        XCTAssertEqual(SortOrder(rawValue: "Oldest → Newest"), .ascending)
        XCTAssertEqual(SortOrder(rawValue: "Newest → Oldest"), .descending)
        XCTAssertNil(SortOrder(rawValue: "invalid"))
    }

    // MARK: - TemperatureUnit

    func testTemperatureUnit_allCasesCount() {
        XCTAssertEqual(TemperatureUnit.allCases.count, 2)
    }

    func testTemperatureUnit_rawValues() {
        XCTAssertEqual(TemperatureUnit.celsius.rawValue, "Celsius (°C)")
        XCTAssertEqual(TemperatureUnit.fahrenheit.rawValue, "Fahrenheit (°F)")
    }

    func testTemperatureUnit_initFromRawValue() {
        XCTAssertEqual(TemperatureUnit(rawValue: "Celsius (°C)"), .celsius)
        XCTAssertEqual(TemperatureUnit(rawValue: "Fahrenheit (°F)"), .fahrenheit)
        XCTAssertNil(TemperatureUnit(rawValue: "invalid"))
    }

    // MARK: - WeightUnit

    func testWeightUnit_allCasesCount() {
        XCTAssertEqual(WeightUnit.allCases.count, 2)
    }

    func testWeightUnit_rawValues() {
        XCTAssertEqual(WeightUnit.kilograms.rawValue, "Kilograms (kg)")
        XCTAssertEqual(WeightUnit.pounds.rawValue, "Pounds (lbs)")
    }

    func testWeightUnit_initFromRawValue() {
        XCTAssertEqual(WeightUnit(rawValue: "Kilograms (kg)"), .kilograms)
        XCTAssertEqual(WeightUnit(rawValue: "Pounds (lbs)"), .pounds)
        XCTAssertNil(WeightUnit(rawValue: "invalid"))
    }
}
