import SwiftUI

struct LaunchView: View {
    @ObservedObject var settings: SettingsManager
    @State private var showingSettings = false
    @ScaledMetric(relativeTo: .body) private var glyphWidth: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var sectionSpacing: CGFloat = 32
    @ScaledMetric(relativeTo: .body) private var rowSpacing: CGFloat = 18

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(version) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: sectionSpacing) {
                header

                VStack(alignment: .leading, spacing: rowSpacing) {
                    categoryRow(
                        systemImage: "figure.walk",
                        title: "Body measurements and activity",
                        detail: "Weight and steps."
                    )
                    categoryRow(
                        systemImage: "drop",
                        title: "Blood glucose",
                        detail: "With before-meal and after-meal tags."
                    )
                    categoryRow(
                        systemImage: "heart.text.square",
                        title: "Vitals",
                        detail: "Blood pressure, heart rate, oxygen saturation and more."
                    )
                    categoryRow(
                        systemImage: "cross.case",
                        title: "Lab results",
                        detail: "From Clinical Health Records, identified by LOINC code."
                    )
                }

                privacyLine

                aboutLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color("Paper").ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .navigationTitle("HealthExporterCSV")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("HealthExporterCSV")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("appTitle")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("settingsButton")
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(settings: settings)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export your health record")
                .font(.largeTitle)
                .fontWeight(.semibold)
                .fontDesign(.serif)
                .foregroundStyle(Color("Ink"))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text("Choose the data you want. The app writes it to one CSV file on this iPhone.")
                .font(.body)
                .foregroundStyle(Color("InkSecondary"))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func categoryRow(systemImage: String, title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(.tint)
                .frame(width: glyphWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(Color("Ink"))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color("InkSecondary"))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var privacyLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: "lock")
                .font(.body)
                .foregroundStyle(Color("InkSecondary"))
                .frame(width: glyphWidth)
                .accessibilityHidden(true)
            Text("Everything happens on your iPhone. No accounts, no servers, no tracking.")
                .font(.subheadline)
                .foregroundStyle(Color("InkSecondary"))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var aboutLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            Link("Report a Problem", destination: URL(string: "https://github.com/evanwtf/HealthExporter/issues/new?template=bug_report.md")!)
                .font(.footnote)
                .accessibilityIdentifier("reportProblemLink")
            Text("\(versionText) \u{00B7} \u{00A9} \(String(Calendar.current.component(.year, from: Date()))) Evan Hoffman")
                .font(.footnote)
                .foregroundStyle(Color("InkSecondary"))
        }
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink(destination: DataSelectionView(settings: settings)) {
                Text("Choose Data")
                    .fontWeight(.semibold)
                    .foregroundStyle(Color("OnAccent"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .controlSize(.large)
            .accessibilityIdentifier("nextButton")

        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color("Paper"))
    }
}

struct LaunchView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            LaunchView(settings: SettingsManager())
        }
    }
}
