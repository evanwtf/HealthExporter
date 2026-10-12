import SwiftUI

struct LaunchView: View {
    @ObservedObject var settings: SettingsManager
    @Binding var isLaunching: Bool
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image("AppIconImage")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(radius: 8)

            Text("HealthExporterCSV")
                .font(.largeTitle)
                .fontWeight(.bold)
                .accessibilityIdentifier("appTitle")

            if isLaunching {
                ProgressView()
                    .scaleEffect(1.2)
                    .transition(.opacity)
            } else {
                VStack(spacing: 16) {
                    Text("Export your health data to CSV")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    NavigationLink(destination: DataSelectionView(settings: settings)) {
                        Text("Next")
                            .font(.title)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .accessibilityIdentifier("nextButton")

                }
                .transition(.opacity)
            }

            Spacer()

            if !isLaunching {
                VStack(spacing: 12) {
                    Button(action: {
                        showingSettings = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "gear")
                            Text("Settings")
                        }
                        .font(.body)
                        .foregroundColor(.blue)
                    }
                    .accessibilityIdentifier("settingsButton")

                    Link(destination: URL(string: "https://github.com/evanwtf/HealthExporter/issues/new?template=bug_report.md")!) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.bubble")
                            Text("Report a Problem")
                        }
                        .font(.body)
                        .foregroundColor(.blue)
                    }
                    .accessibilityIdentifier("reportProblemLink")
                }
                .transition(.opacity)
            }

            VStack(spacing: 4) {
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Text("\u{00A9} \(String(Calendar.current.component(.year, from: Date()))) Evan Hoffman")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 32)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(settings: settings)
        }
    }
}

struct LaunchView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NavigationStack {
                LaunchView(settings: SettingsManager(), isLaunching: .constant(true))
            }
            .previewDisplayName("Launching")

            NavigationStack {
                LaunchView(settings: SettingsManager(), isLaunching: .constant(false))
            }
            .previewDisplayName("Ready")
        }
    }
}
