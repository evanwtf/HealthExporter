import Foundation
@testable import HealthExporter
import Testing

/// The app and the web page show the same privacy policy. These tests read
/// `docs/privacy-policy.md` from the checkout: the simulator runs on the same
/// Mac, so it can read the source tree.
struct PrivacyPolicyTests {
    private static let webPolicyURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "docs/privacy-policy.md")

    private static func webLines() throws -> [String] {
        try String(contentsOf: webPolicyURL, encoding: .utf8)
            .components(separatedBy: .newlines)
    }

    @Test func webPolicy_hasTheSameDate() throws {
        #expect(try Self.webLines().contains("**Last updated:** \(PrivacyPolicy.lastUpdated)"))
    }

    @Test(arguments: PrivacyPolicy.allSections)
    func webPolicy_hasEveryLineOfTheSection(_ section: PolicySection) throws {
        let lines = try Self.webLines()
        #expect(lines.contains("## \(section.title)"))
        #expect(lines.contains(section.body))
        for bullet in section.bullets {
            #expect(lines.contains("- \(bullet)"))
        }
        if let closing = section.closing {
            #expect(lines.contains(closing))
        }
    }

    /// A section added to one copy only fails here.
    @Test func webPolicy_hasTheSameSectionsInTheSameOrder() throws {
        let headings = try Self.webLines()
            .filter { $0.hasPrefix("## ") }
            .map { String($0.dropFirst(3)) }
        #expect(headings == PrivacyPolicy.allSections.map(\.title))
    }

    @Test(arguments: PrivacyPolicy.allSections)
    func links_renderAsLinks(_ section: PolicySection) {
        let texts = [section.body] + section.bullets + [section.closing].compactMap(\.self)
        for text in texts where text.contains("](") {
            let rendered = PrivacyPolicyView.markdown(text)
            #expect(rendered.runs.contains { $0.link != nil })
            #expect(!String(rendered.characters).contains("]("))
        }
    }
}
