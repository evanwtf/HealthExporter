import SwiftUI

/// One switch in a `SelectionDetailView`.
struct SelectionDetailRow: Identifiable {
    let id: String
    let title: String
    let caption: String?
    let accessibilityIdentifier: String
    let isOn: Binding<Bool>
}

/// The individual labs of one panel, or the individual vitals. The rows carry
/// the bindings from `DataSelectionView`, so the selection rules stay there.
struct SelectionDetailView: View {
    @ObservedObject var settings: SettingsManager
    let title: String
    let category: HealthCategory
    let rows: [SelectionDetailRow]

    var body: some View {
        List {
            Section {
                ForEach(rows) { row in
                    Toggle(isOn: row.isOn) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                            if let caption = row.caption {
                                Text(caption)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .tint(category.color)
                    .accessibilityIdentifier(row.accessibilityIdentifier)
                }
            }
        }
        .fontDesign(.rounded)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(title)
                    .font(.headline)
                    .fontDesign(.rounded)
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }
}
