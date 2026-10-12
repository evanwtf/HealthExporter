import Foundation
@testable import HealthExporter
import Testing

struct DateRangeOptionTests {
    @Test func allCasesCount() {
        #expect(DateRangeOption.allCases.count == 4)
    }

    @Test func allCasesExist() {
        let cases = DateRangeOption.allCases
        #expect(cases.contains(.lastXDays))
        #expect(cases.contains(.lastXRecords))
        #expect(cases.contains(.specificDateRange))
        #expect(cases.contains(.allRecords))
    }

    @Test func rawValues() {
        #expect(DateRangeOption.lastXDays.rawValue == "Last X Days")
        #expect(DateRangeOption.lastXRecords.rawValue == "Last X Records")
        #expect(DateRangeOption.specificDateRange.rawValue == "Specific Date Range")
        #expect(DateRangeOption.allRecords.rawValue == "All Records")
    }

    @Test func displayNameMatchesRawValue() {
        for option in DateRangeOption.allCases {
            #expect(option.displayName == option.rawValue, "\(option) displayName should equal its rawValue")
        }
    }

    @Test func initFromValidRawValue() {
        #expect(DateRangeOption(rawValue: "Last X Days") == .lastXDays)
        #expect(DateRangeOption(rawValue: "Last X Records") == .lastXRecords)
        #expect(DateRangeOption(rawValue: "Specific Date Range") == .specificDateRange)
        #expect(DateRangeOption(rawValue: "All Records") == .allRecords)
    }

    @Test func initFromInvalidRawValue_returnsNil() {
        #expect(DateRangeOption(rawValue: "Invalid") == nil)
        #expect(DateRangeOption(rawValue: "") == nil)
        #expect(DateRangeOption(rawValue: "last x days") == nil) // case-sensitive
    }
}
