import SwiftUI

/// What one export held: a line per category with the Choose Data tile icon
/// and color, then the date range, the size and the metrics that did not load.
struct ExportHistoryEntryView: View {
    let entry: ExportHistoryEntry

    private struct CategoryLine {
        let category: HealthCategory
        let text: String
    }

    private var categoryLines: [CategoryLine] {
        var lines: [CategoryLine] = []
        if entry.exportWeight {
            lines.append(CategoryLine(category: .weight, text: HealthCategory.weight.name))
        }
        if entry.exportSteps {
            lines.append(CategoryLine(category: .steps, text: HealthCategory.steps.name))
        }
        if entry.exportGlucose {
            lines.append(CategoryLine(category: .glucose, text: HealthCategory.glucose.name))
        }
        let vitals = entry.knownVitalMetrics
        if vitals.count == VitalMetric.allCases.count {
            lines.append(CategoryLine(category: .vitals, text: "All vitals"))
        } else if !vitals.isEmpty {
            lines.append(CategoryLine(category: .vitals, text: vitals.map(\.displayName).joined(separator: ", ")))
        }
        let labNames = entry.knownLabPanels.map(\.displayName) + entry.labMetricsOutsideSelectedPanels.map(\.name)
        if !labNames.isEmpty {
            lines.append(CategoryLine(category: .labs, text: labNames.joined(separator: ", ")))
        }
        return lines
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(categoryLines, id: \.category) { line in
                Label {
                    Text(line.text)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: line.category.systemImage)
                        .foregroundStyle(line.category.color)
                }
                .font(.body)
            }

            Group {
                Label(entry.dateRange.text(), systemImage: "calendar")
                Label(entry.sizeText, systemImage: "doc.text")
                    .monospacedDigit()
            }
            .font(.subheadline)
            .foregroundStyle(Color("SecondaryText"))

            if !entry.failedMetrics.isEmpty {
                Label {
                    Text("Did not load: \(entry.failedMetrics.joined(separator: ", "))")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.subheadline)
                .foregroundStyle(Color("ErrorText"))
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
