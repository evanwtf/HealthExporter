import SwiftUI

/// The last 10 exports, newest first, as a sheet from the welcome screen.
/// Export Again calls `onExportAgain`; the welcome screen then opens Choose Data.
struct ExportHistoryView: View {
    let settings: SettingsManager
    let onExportAgain: (ExportHistoryEntry) -> Void
    /// Screenshots pass a fixed time, so "Today" does not depend on the clock.
    var fixedNow: Date?

    @Environment(\.dismiss) private var dismiss
    @State private var showingClearConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if settings.exportHistory.isEmpty {
                    emptyState
                } else {
                    entryList
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .fontDesign(.rounded)
            .tint(Color("AccentColor"))
            .navigationTitle("Export History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) {
                        dismiss()
                    }
                    .accessibilityIdentifier("historyCloseButton")
                }
            }
        }
    }

    private var entryList: some View {
        let now = fixedNow ?? Date()
        return List {
            ForEach(settings.exportHistory.entries) { entry in
                Section {
                    ExportHistoryEntryView(entry: entry)
                    Button {
                        onExportAgain(entry)
                    } label: {
                        Label("Export Again", systemImage: "arrow.clockwise")
                            .fontWeight(.semibold)
                    }
                    .accessibilityIdentifier("exportAgainButton")
                } header: {
                    Text(ExportHistoryDateText.text(for: entry.date, now: now, startsSentence: true))
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                        .textCase(nil)
                }
            }

            Section {
                Button("Clear History", role: .destructive) {
                    showingClearConfirmation = true
                }
                .accessibilityIdentifier("clearHistoryButton")
            } footer: {
                Text("The app keeps your last \(ExportHistory.maxEntries) exports on this iPhone. An entry holds no health data.")
            }
        }
        .listStyle(.insetGrouped)
        .confirmationDialog("Clear export history?", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) {
                settings.clearExportHistory()
            }
        } message: {
            Text("This removes every entry. Your saved files do not change.")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No exports yet", systemImage: "clock.arrow.circlepath")
        } description: {
            if settings.keepExportHistory {
                Text("Each file you save appears here, with what it held, its date range and its size. Tap Export Again to export the same data again.")
            } else {
                Text("Keep Export History is off. Turn it on in Settings to keep a list of your exports.")
            }
        }
        .accessibilityIdentifier("historyEmptyState")
    }
}

#Preview {
    ExportHistoryView(settings: SettingsManager(), onExportAgain: { _ in })
}
