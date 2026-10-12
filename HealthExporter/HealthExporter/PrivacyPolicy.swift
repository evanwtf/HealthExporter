import Foundation

/// One section of the privacy policy or the disclaimer. Text may hold inline
/// Markdown links, which both the app and the web page render.
nonisolated struct PolicySection: Hashable, Sendable {
    let title: String
    let body: String
    var bullets: [String] = []
    var closing: String?
}

/// The privacy policy and the disclaimer that Settings shows. The web copy,
/// `docs/privacy-policy.md`, must say the same thing: `PrivacyPolicyTests`
/// checks every line here against it. Change both in the same commit.
nonisolated enum PrivacyPolicy {
    static let lastUpdated = "October 2026"

    static let policy: [PolicySection] = [
        PolicySection(
            title: "Overview",
            body: "HealthExporterCSV is designed with your privacy as a core principle. All data processing happens entirely on your device. No health data is ever sent to external servers, collected by the developer, or shared with third parties."
        ),
        PolicySection(
            title: "Data We Access",
            body: "HealthExporterCSV asks for read-only access to Apple Health. It asks only for the data types you select for an export:",
            bullets: [
                "Weight",
                "Step Count",
                "Blood Glucose, with the meal time (before or after a meal) when a reading has one",
                "Vitals: blood pressure, resting heart rate, heart rate variability, oxygen saturation, respiratory rate, and body temperature",
                "Lab results from Health Records, such as Hemoglobin A1C, lipid panel, CBC, CMP / BMP, and thyroid labs",
            ],
            closing: "For each value, the app also reads its date, its unit, and its source: the app or device that recorded it. Apple gives access to lab results as one data type, so the app reads the lab results in your date range and keeps only the labs you selected. You control exactly which data types to share through the Apple Health permissions dialog."
        ),
        PolicySection(
            title: "How Your Data Is Used",
            body: "Your health data is used solely to generate CSV export files on your device. Specifically:",
            bullets: [
                "Data is read from Apple Health only when you start an export.",
                "The app builds the CSV file in memory and passes it to the system file picker. The app does not keep a copy.",
                "The app clears health data from memory after the export, and also when you cancel or the export fails.",
                "No health data is stored persistently by the app.",
                "On iOS 27 and later, you can limit an app to data from a start date. The app reads that date only to warn you when your export starts earlier.",
            ]
        ),
        PolicySection(
            title: "Exported Files",
            body: "The CSV file holds your health data as plain text, and it is not encrypted. You choose where to save it in the file picker, for example On My iPhone, iCloud Drive, or another storage app, and the privacy terms of that place apply. After you save the file, HealthExporterCSV cannot see, change, or delete it. Share the file only with people you trust, such as your doctor."
        ),
        PolicySection(
            title: "Data Storage",
            body: "The only data HealthExporterCSV stores persistently is your settings, in the app's local UserDefaults: units, date format, sort order, the metrics, vitals, lab panels, and labs you selected, and your date range choices. No health data, personal identifiers, or usage analytics are stored. Deleting the app deletes these settings."
        ),
        PolicySection(
            title: "No Data Collection or Transmission",
            body: "HealthExporterCSV does not:",
            bullets: [
                "Collect or transmit any data to external servers",
                "Include analytics, crash reporting, or tracking SDKs",
                "Require or support user accounts",
                "Use advertising or marketing frameworks",
                "Share data with any third parties",
            ]
        ),
        PolicySection(
            title: "Report a Problem",
            body: "The Report a Problem link on the welcome screen opens a GitHub page in your browser. The app sends no data with it. GitHub issues are public, so do not put health data, screenshots of your data, or exported files in an issue. GitHub's privacy policy applies to anything you post there."
        ),
        PolicySection(
            title: "Your Control",
            body: "You can turn off HealthExporterCSV's access to Apple Health at any time. Open the Health app, tap your profile picture, then under Privacy tap Apps, and tap HealthExporterCSV. Turning off access does not affect any CSV files you have already exported."
        ),
        PolicySection(
            title: "Changes to This Policy",
            body: "If this privacy policy changes, the new version is included in an app update and posted at [evanwtf.github.io/HealthExporter/privacy-policy](https://evanwtf.github.io/HealthExporter/privacy-policy/). The \"Last updated\" date at the top shows the most recent change."
        ),
    ]

    static let disclaimer: [PolicySection] = [
        PolicySection(
            title: "No Warranty",
            body: "HealthExporterCSV is provided \"as is\" without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and noninfringement."
        ),
        PolicySection(
            title: "Not Medical Advice",
            body: "HealthExporterCSV is a data export utility. It does not provide medical advice, diagnosis, or treatment recommendations. The exported data is a reflection of what is stored in Apple HealthKit and should not be used as a substitute for professional medical judgment. Always consult a qualified healthcare provider with questions about your health."
        ),
        PolicySection(
            title: "Limitation of Liability",
            body: "In no event shall the developer be liable for any claim, damages, or other liability arising from the use or inability to use this app, including but not limited to data loss, inaccurate exports, or any decisions made based on exported data."
        ),
        PolicySection(
            title: "Data Accuracy",
            body: "HealthExporterCSV exports data as recorded in Apple HealthKit. The developer makes no guarantees about the accuracy, completeness, or reliability of the underlying health data or the exported CSV files."
        ),
    ]

    static let contact = PolicySection(
        title: "Contact",
        body: "For questions about this privacy policy, open an issue at [github.com/evanwtf/HealthExporter/issues](https://github.com/evanwtf/HealthExporter/issues). Issues are public."
    )

    /// Every section, in page order.
    static var allSections: [PolicySection] {
        policy + disclaimer + [contact]
    }
}
