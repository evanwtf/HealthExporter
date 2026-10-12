import Foundation

nonisolated enum ExportError: LocalizedError {
    case healthKitAuthorizationFailed(underlying: Error?)
    case healthKitQueryFailed(metric: String, underlying: Error?)
    case noDataFound
    case fileWriteFailed(underlying: Error?)

    var errorDescription: String? {
        switch self {
        case .healthKitAuthorizationFailed(let underlying):
            if let underlying = underlying {
                return "HealthKit authorization failed: \(underlying.localizedDescription)"
            }
            return "HealthKit authorization was denied."
        case .healthKitQueryFailed(let metric, let underlying):
            if let underlying = underlying {
                return "Failed to fetch \(metric) data: \(underlying.localizedDescription)"
            }
            return "Failed to fetch \(metric) data."
        case .noDataFound:
            return "No data found for the selected metrics and date range."
        case .fileWriteFailed(let underlying):
            if let underlying = underlying {
                return "Failed to save the CSV file: \(underlying.localizedDescription)"
            }
            return "Failed to save the CSV file."
        }
    }
}
