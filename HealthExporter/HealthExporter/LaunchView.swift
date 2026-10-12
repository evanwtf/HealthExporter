import SwiftUI

struct LaunchView: View {
    @ObservedObject var settings: SettingsManager
    @State private var showingSettings = false

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(version) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                categoryRow
                privacyLine
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .fontDesign(.rounded)
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
                .accessibilityHidden(true)

            Text("HealthExporterCSV")
                .font(.largeTitle.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityIdentifier("appTitle")

            Text("Export your Apple Health data to one CSV file.")
                .font(.title3)
                .foregroundStyle(Color("SecondaryText"))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var categoryRow: some View {
        HStack(spacing: 0) {
            ForEach(HealthCategory.allCases, id: \.self) { category in
                Image(systemName: category.systemImage)
                    .font(.title)
                    .foregroundStyle(category.color)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weight, steps, blood glucose, vitals and lab results")
    }

    private var privacyLine: some View {
        Label {
            Text("**Private by design.** Everything happens on your iPhone. No accounts, no servers, no tracking.")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock.fill")
                .foregroundStyle(.tint)
        }
        .font(.subheadline)
        .foregroundStyle(Color("SecondaryText"))
        .multilineTextAlignment(.leading)
    }

    private var bottomBar: some View {
        VStack(spacing: 16) {
            NavigationLink(destination: DataSelectionView(settings: settings)) {
                Text("Choose Data")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(.accentColor)
            .controlSize(.large)
            .accessibilityIdentifier("nextButton")

            VStack(spacing: 4) {
                Link("Report a Problem", destination: URL(string: "https://github.com/evanwtf/HealthExporter/issues/new?template=bug_report.md")!)
                    .font(.footnote)
                    .accessibilityIdentifier("reportProblemLink")
                Text("\(versionText) \u{00B7} \u{00A9} \(String(Calendar.current.component(.year, from: Date()))) Evan Hoffman")
                    .font(.footnote)
                    .foregroundStyle(Color("SecondaryText"))
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
