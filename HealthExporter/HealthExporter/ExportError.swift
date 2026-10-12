import Foundation

nonisolated enum ExportError: LocalizedError {
    case healthKitAuthorizationFailed(underlying: Error?)
    case healthKitQueryFailed(metric: String, underlying: Error?)
    case noDataFound
    case fileWriteFailed(underlying: Error?)

    var errorDescription: String? {
        switch self {
        case let .healthKitAuthorizationFailed(underlying):
            if let underlying {
                return "HealthKit authorization failed: \(underlying.localizedDescription)"
            }
            return "HealthKit authorization was denied."
        case let .healthKitQueryFailed(metric, underlying):
            if let underlying {
                return "Failed to fetch \(metric) data: \(underlying.localizedDescription)"
            }
            return "Failed to fetch \(metric) data."
        case .noDataFound:
            return "No data found for the selected metrics and date range."
        case let .fileWriteFailed(underlying):
            if let underlying {
                return "Failed to save the CSV file: \(underlying.localizedDescription)"
            }
            return "Failed to save the CSV file."
        }
    }
}
