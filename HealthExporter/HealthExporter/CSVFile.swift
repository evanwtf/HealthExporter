import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// One built CSV export. The file picker (`fileExporter(item:)`) writes
/// `content` as UTF-8 through the transfer representation.
nonisolated struct CSVFile: Transferable, Sendable {
    let content: String
    /// One row per sample; the preamble lines are not rows.
    let rowCount: Int
    /// The size of the file, in UTF-8 bytes.
    let byteCount: Int

    init(content: String, rowCount: Int) {
        self.content = content
        self.rowCount = rowCount
        self.byteCount = content.utf8.count
    }

    var size: ExportSize {
        ExportSize(rowCount: rowCount, byteCount: byteCount)
    }

    var data: Data {
        Data(content.utf8)
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { file in
            file.data
        }
    }
}
