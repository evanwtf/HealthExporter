import Foundation

/// The date range of one export, as the user chose it in Choose Data.
/// Export Again uses it to set the date range controls again.
nonisolated enum ExportHistoryDateRange: Codable, Equatable, Sendable {
    case lastDays(Int)
    case lastRecords(Int)
    case specific(start: Date, end: Date)
    case allRecords

    /// Reads the date range controls of Choose Data.
    init(option: DateRangeOption, lastXDays: Int, lastXRecords: Int, startDate: Date, endDate: Date) {
        switch option {
        case .lastXDays: self = .lastDays(lastXDays)
        case .lastXRecords: self = .lastRecords(lastXRecords)
        case .specificDateRange: self = .specific(start: startDate, end: endDate)
        case .allRecords: self = .allRecords
        }
    }

    var option: DateRangeOption {
        switch self {
        case .lastDays: .lastXDays
        case .lastRecords: .lastXRecords
        case .specific: .specificDateRange
        case .allRecords: .allRecords
        }
    }

    /// The start date for the "Range" controls, or nil for the other options.
    var specificStart: Date? {
        if case let .specific(start, _) = self {
            return start
        }
        return nil
    }

    /// The end date for the "Range" controls, or nil for the other options.
    var specificEnd: Date? {
        if case let .specific(_, end) = self {
            return end
        }
        return nil
    }

    /// For example "Last 30 days", "Oct 1, 2026 to Oct 12, 2026" or "All records".
    func text(dateStyle: Date.FormatStyle = Date.FormatStyle(date: .abbreviated, time: .omitted)) -> String {
        switch self {
        case let .lastDays(days):
            days == 1 ? "Last day" : "Last \(days.formatted()) days"
        case let .lastRecords(records):
            records == 1 ? "Last record" : "Last \(records.formatted()) records"
        case let .specific(start, end):
            "\(start.formatted(dateStyle)) to \(end.formatted(dateStyle))"
        case .allRecords:
            "All records"
        }
    }
}
