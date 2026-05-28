import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Group {
                    Text("Privacy Policy")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Last updated: March 2026")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    sectionView(title: "Overview",
                        body: "HealthExporterCSV is designed with your privacy as a core principle. All data processing happens entirely on your device. No health data is ever sent to external servers, collected by the developer, or shared with third parties.")

                    sectionView(title: "Data We Access",
                        body: """
                        HealthExporterCSV requests read-only access to the following Apple HealthKit data types, only when you explicitly grant permission:

                        • Weight
                        • Step Count
                        • Blood Glucose
                        • Selected clinical lab results, such as Hemoglobin A1C and lipid panel labs

                        You control exactly which data types to share through the Apple Health permissions dialog.
                        """)

                    sectionView(title: "How Your Data Is Used",
                        body: """
                        Your health data is used solely to generate CSV export files on your device. Specifically:

                        • Data is read from HealthKit only when you initiate an export.
                        • The CSV file is generated in memory and presented through the system file picker.
                        • Health data is cleared from app memory immediately after export.
                        • No health data is stored persistently by the app.
                        """)
                }

                Group {
                    sectionView(title: "Data Storage",
                        body: "The only data HealthExporterCSV stores persistently is your preferences (unit selections, date format, sort order, and metric toggle states) in the app's local UserDefaults. No health data, personal identifiers, or usage analytics are stored.")

                    sectionView(title: "No Data Collection or Transmission",
                        body: """
                        HealthExporterCSV does not:

                        • Collect or transmit any data to external servers
                        • Include analytics, crash reporting, or tracking SDKs
                        • Require or support user accounts
                        • Use advertising or marketing frameworks
                        • Share data with any third parties
                        """)

                    sectionView(title: "Your Control",
                        body: "You can revoke HealthExporterCSV's access to HealthKit data at any time through Settings > Health > Data Access & Devices on your iPhone. Revoking access does not affect any CSV files you have previously exported.")

                    sectionView(title: "Changes to This Policy",
                        body: "If this privacy policy is updated, the revised version will be included in an app update. The \"Last updated\" date at the top will reflect the most recent revision.")
                }

                Divider()
                    .padding(.vertical, 8)

                Group {
                    Text("Disclaimer")
                        .font(.title)
                        .fontWeight(.bold)

                    sectionView(title: "No Warranty",
                        body: "HealthExporterCSV is provided \"as is\" without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and noninfringement.")

                    sectionView(title: "Not Medical Advice",
                        body: "HealthExporterCSV is a data export utility. It does not provide medical advice, diagnosis, or treatment recommendations. The exported data is a reflection of what is stored in Apple HealthKit and should not be used as a substitute for professional medical judgment. Always consult a qualified healthcare provider with questions about your health.")

                    sectionView(title: "Limitation of Liability",
                        body: "In no event shall the developer be liable for any claim, damages, or other liability arising from the use or inability to use this app, including but not limited to data loss, inaccurate exports, or any decisions made based on exported data.")

                    sectionView(title: "Data Accuracy",
                        body: "HealthExporterCSV exports data as recorded in Apple HealthKit. The developer makes no guarantees about the accuracy, completeness, or reliability of the underlying health data or the exported CSV files.")
                }
            }
            .padding()
        }
        .navigationTitle("Privacy & Disclaimer")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sectionView(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
}

struct PrivacyPolicyView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            PrivacyPolicyView()
        }
    }
}
