import SwiftUI

struct LaunchView: View {
    let settings: SettingsManager
    /// Screenshots pass a fixed time for the "Last export" line.
    var fixedNow: Date?

    @State private var showingSettings = false
    @State private var showingHistory = false
    @State private var showingDataSelection = false
    /// The date range that Choose Data opens with. Nil opens it on Days.
    @State private var dataSelectionRange: ExportHistoryDateRange?
    /// Set by Export Again. Choose Data opens after the history sheet closes.
    @State private var exportAgainRange: ExportHistoryDateRange?

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
                if let latest = settings.exportHistory.latest {
                    lastExportLine(latest)
                }
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
        .tint(Color("AccentColor"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingHistory = true
                } label: {
                    Label("Export History", systemImage: "clock.arrow.circlepath")
                }
                .accessibilityLabel("Export History")
                .accessibilityIdentifier("historyButton")
            }
            // Two glass buttons, each like the Settings gear on its own.
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
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
        .sheet(isPresented: $showingHistory, onDismiss: openExportAgain) {
            ExportHistoryView(settings: settings, onExportAgain: exportAgain, fixedNow: fixedNow)
        }
        .navigationDestination(isPresented: $showingDataSelection) {
            DataSelectionView(settings: settings, initialDateRange: dataSelectionRange)
        }
    }

    /// Restores the entry's selection now. Choose Data opens when the sheet is gone.
    private func exportAgain(_ entry: ExportHistoryEntry) {
        exportAgainRange = settings.restoreSelection(from: entry)
        showingHistory = false
    }

    private func openExportAgain() {
        guard let range = exportAgainRange else { return }
        exportAgainRange = nil
        dataSelectionRange = range
        showingDataSelection = true
    }

    private func lastExportLine(_ entry: ExportHistoryEntry) -> some View {
        Button {
            showingHistory = true
        } label: {
            HStack(spacing: 8) {
                Label {
                    Text("Last export: \(ExportHistoryDateText.text(for: entry.date, now: fixedNow ?? Date()))")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.tint)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color("SecondaryText"))
                    .accessibilityHidden(true)
            }
            .font(.subheadline)
            .foregroundStyle(Color.primary)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            // The welcome screen is systemBackground, so the grouped color would be white on white.
            .background(
                Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens your export history")
        .accessibilityIdentifier("lastExportLine")
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
            Button {
                dataSelectionRange = nil
                showingDataSelection = true
            } label: {
                Text("Choose Data")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(Color("AccentColor"))
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

#Preview {
    NavigationStack {
        LaunchView(settings: SettingsManager())
    }
}
