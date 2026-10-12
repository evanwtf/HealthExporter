import Foundation

nonisolated enum DateRangeOption: String, CaseIterable {
    case lastXDays = "Last X Days"
    case lastXRecords = "Last X Records"
    case specificDateRange = "Specific Date Range"
    case allRecords = "All Records"
    
    var displayName: String {
        self.rawValue
    }
}
