import Foundation

/// The exact size of a built export. A large export asks the user to confirm
/// before the file picker opens.
nonisolated struct ExportSize: Equatable, Sendable {
    static let confirmationRowThreshold = 500
    static let confirmationByteThreshold = 1_000_000

    let rowCount: Int
    let byteCount: Int

    var formattedRowCount: String {
        rowCount.formatted()
    }

    var formattedByteCount: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    var summaryText: String {
        "This will export \(formattedRowCount) \(rowCount == 1 ? "row" : "rows") (\(formattedByteCount))."
    }

    var shouldShowConfirmation: Bool {
        rowCount > Self.confirmationRowThreshold || byteCount > Self.confirmationByteThreshold
    }
}
