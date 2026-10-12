import Foundation
@testable import HealthExporter
import Testing

struct ExportErrorTests {
    // MARK: - healthKitAuthorizationFailed

    @Test func authorizationFailed_withoutUnderlyingError() {
        let error = ExportError.healthKitAuthorizationFailed(underlying: nil)
        #expect(error.errorDescription == "HealthKit authorization was denied.")
    }

    @Test func authorizationFailed_withUnderlyingError() {
        let underlying = NSError(domain: "HKErrorDomain", code: 5, userInfo: [
            NSLocalizedDescriptionKey: "Access denied",
        ])
        let error = ExportError.healthKitAuthorizationFailed(underlying: underlying)
        #expect(error.errorDescription == "HealthKit authorization failed: Access denied")
    }

    // MARK: - healthKitQueryFailed

    @Test func queryFailed_withoutUnderlyingError() {
        let error = ExportError.healthKitQueryFailed(metric: "Hemoglobin A1C", underlying: nil)
        #expect(error.errorDescription == "Failed to fetch Hemoglobin A1C data.")
    }

    @Test func queryFailed_withUnderlyingError() {
        let underlying = NSError(domain: "HKErrorDomain", code: 6, userInfo: [
            NSLocalizedDescriptionKey: "Unavailable",
        ])
        let error = ExportError.healthKitQueryFailed(metric: "Weight", underlying: underlying)
        #expect(error.errorDescription == "Failed to fetch Weight data: Unavailable")
    }

    // MARK: - noDataFound

    @Test func noDataFound() {
        let error = ExportError.noDataFound
        #expect(error.errorDescription == "No data found for the selected metrics and date range.")
    }

    // MARK: - fileWriteFailed

    @Test func fileWriteFailed_withoutUnderlyingError() {
        let error = ExportError.fileWriteFailed(underlying: nil)
        #expect(error.errorDescription == "Failed to save the CSV file.")
    }

    @Test func fileWriteFailed_withUnderlyingError() {
        let underlying = NSError(domain: NSCocoaErrorDomain, code: 4, userInfo: [
            NSLocalizedDescriptionKey: "Disk full",
        ])
        let error = ExportError.fileWriteFailed(underlying: underlying)
        #expect(error.errorDescription == "Failed to save the CSV file: Disk full")
    }

    // MARK: - LocalizedError conformance

    @Test func conformsToLocalizedError() {
        let error: LocalizedError = ExportError.noDataFound
        #expect(error.errorDescription != nil)
    }
}
