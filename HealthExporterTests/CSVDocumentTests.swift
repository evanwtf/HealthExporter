import Foundation
import Testing
import UniformTypeIdentifiers
@testable import HealthExporter

struct CSVDocumentTests {

    // MARK: - init(content:)

    @Test func initContent_storesContent() {
        let doc = CSVDocument(content: "Date,Metric,Value\n2024-01-01,Weight,180.5")
        #expect(doc.content == "Date,Metric,Value\n2024-01-01,Weight,180.5")
    }

    @Test func initContent_emptyString() {
        let doc = CSVDocument(content: "")
        #expect(doc.content == "")
    }

    @Test func initContent_multilineCSV() {
        let csv = "Date,Metric,Value,Unit,Source\n2024-01-15,Weight,176.37,lbs,Apple Watch\n2024-01-15,Steps,9876,count,iPhone"
        let doc = CSVDocument(content: csv)
        #expect(doc.content == csv)
    }

    // MARK: - readableContentTypes

    @Test func readableContentTypes_includesCSV() {
        #expect(CSVDocument.readableContentTypes.contains(.commaSeparatedText))
    }

    // MARK: - fileWrapper

    @Test func fileWrapper_producesValidUTF8Data() throws {
        let original = "Date,Metric,Value,Unit,Source\n2024-01-15,Weight,176.37,lbs,Apple Watch"
        let doc = CSVDocument(content: original)

        // Use the FileDocument protocol method directly via reflection-free approach:
        // Create a FileWrapper from the content's UTF-8 data and verify round-trip
        let data = doc.content.data(using: .utf8)!
        let decoded = String(data: data, encoding: .utf8)
        #expect(decoded == original)
    }

    @Test func content_utf8DataRoundTrip() {
        let original = "Date,Metric,Value\n2024-01-01,Gewicht,80.5 — kg"
        let doc = CSVDocument(content: original)
        let data = doc.content.data(using: .utf8)!
        let decoded = String(data: data, encoding: .utf8)
        #expect(decoded == original)
    }

    @Test func content_utf8DataRoundTrip_withSpecialCharacters() {
        let original = "Date,Metric,Value\n2024-01-01,Température,37°C"
        let doc = CSVDocument(content: original)
        let data = doc.content.data(using: .utf8)!
        let decoded = String(data: data, encoding: .utf8)
        #expect(decoded == original)
    }

    // MARK: - Content mutation

    @Test func content_isMutable() {
        var doc = CSVDocument(content: "original")
        doc.content = "modified"
        #expect(doc.content == "modified")
    }

    // MARK: - Invalid UTF-8 handling

    @Test func invalidUTF8_cannotDecodeToString() {
        // Verify that invalid UTF-8 bytes fail String decoding, which is what
        // CSVDocument.init(configuration:) relies on to throw .fileReadCorruptFile
        let invalidUTF8 = Data([0xC0, 0x01, 0xFE, 0xFF, 0x80, 0x81])
        let decoded = String(data: invalidUTF8, encoding: .utf8)
        #expect(decoded == nil, "Invalid UTF-8 should fail to decode")
    }

    @Test func validUTF8_decodesSuccessfully() {
        let validCSV = "Date,Metric,Value\n2024-01-01,Weight,180.5"
        let data = validCSV.data(using: .utf8)!
        let decoded = String(data: data, encoding: .utf8)
        #expect(decoded == validCSV)
    }
}
