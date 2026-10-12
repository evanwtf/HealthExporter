import SwiftUI

struct LaunchView: View {
    @ObservedObject var settings: SettingsManager
    @State private var showingSettings = false
    @ScaledMetric(relativeTo: .title2) private var featureIconWidth: CGFloat = 36

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(version) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                header
                VStack(alignment: .leading, spacing: 20) {
                    featureRow(
                        systemImage: "lock.shield",
                        title: "Private by design",
                        detail: "Everything happens on your iPhone. No accounts, no servers, no tracking."
                    )
                    featureRow(
                        systemImage: "heart.text.square",
                        title: "Your health data",
                        detail: "Weight, steps, blood glucose, vitals and clinical lab results."
                    )
                    featureRow(
                        systemImage: "tablecells",
                        title: "One CSV file",
                        detail: "Open it in Numbers, Excel or Google Sheets."
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image("AppIconImage")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                .accessibilityHidden(true)

            Text("HealthExporterCSV")
                .font(.largeTitle.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityIdentifier("appTitle")

            Text("Export your health data to CSV")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func featureRow(systemImage: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: featureIconWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var bottomBar: some View {
        VStack(spacing: 16) {
            NavigationLink(destination: DataSelectionView(settings: settings)) {
                Text("Choose Data")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
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
