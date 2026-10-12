import SwiftUI

struct LaunchView: View {
    @ObservedObject var settings: SettingsManager
    @State private var showingSettings = false
    @State private var revealedRows = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(version) (\(build))"
    }

    private static let heroColumns = ["Date", "Metric", "Value", "Unit"]

    /// The header columns the hero shows, read from the real CSV header.
    private static var heroHeader: [String] {
        CSVGenerator.csvHeader
            .components(separatedBy: ",")
            .filter { heroColumns.contains($0) }
    }

    private static let heroRows: [CSVGridView.Row] = [
        .init(id: "weight", cells: ["2026-03-14", "Weight", "182.40", "lbs"]),
        .init(id: "steps", cells: ["2026-03-14", "Steps", "8214", "steps"]),
        .init(id: "glucose", cells: ["2026-03-13", "Blood Glucose", "98", "mg/dL"]),
        .init(id: "a1c", cells: ["2026-02-02", "Hemoglobin A1C", "5.60", "%"]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                CSVGridView(header: Self.heroHeader, rows: Self.heroRows, visibleRowCount: revealedRows)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Example rows")
                    .accessibilityValue("A sample CSV file with a date, metric, value and unit in each row.")

                VStack(alignment: .leading, spacing: 12) {
                    Text("HealthExporterCSV")
                        .font(.title.weight(.semibold))
                        .fontWidth(.expanded)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("appTitle")

                    Text("Export weight, steps, blood glucose, vitals and clinical lab results to one CSV file.")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Label {
                    Text("Everything happens on your iPhone. No accounts, no servers, no tracking.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.tint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .toolbar {
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
        .task {
            await revealHeroRows()
        }
    }

    /// Plays the row entrance once. Under Reduce Motion every row shows at once.
    private func revealHeroRows() async {
        guard revealedRows < Self.heroRows.count else { return }
        if reduceMotion {
            revealedRows = Self.heroRows.count
            return
        }
        while revealedRows < Self.heroRows.count {
            do {
                try await Task.sleep(for: .milliseconds(110))
            } catch {
                revealedRows = Self.heroRows.count
                return
            }
            withAnimation(.easeOut(duration: 0.25)) {
                revealedRows += 1
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 16) {
            NavigationLink(destination: DataSelectionView(settings: settings)) {
                Text("Choose Data")
                    .fontWeight(.semibold)
                    .foregroundStyle(Color("OnAccent"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle)
            .controlSize(.large)
            .accessibilityIdentifier("nextButton")

            VStack(spacing: 4) {
                Link("Report a Problem", destination: URL(string: "https://github.com/evanwtf/HealthExporter/issues/new?template=bug_report.md")!)
                    .font(.footnote)
                    .accessibilityIdentifier("reportProblemLink")
                Text("\(versionText) \u{00B7} \u{00A9} \(String(Calendar.current.component(.year, from: Date()))) Evan Hoffman")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color(uiColor: .systemBackground))
    }
}

struct LaunchView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            LaunchView(settings: SettingsManager())
        }
    }
}
