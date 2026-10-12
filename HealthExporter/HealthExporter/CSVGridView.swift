import SwiftUI

/// Draws CSV text as a small spreadsheet: bordered cells, a tinted header row,
/// and SF Mono cell text. Scrolls sideways when the columns do not fit.
/// `visibleRowCount` hides trailing body rows (for an entrance sequence);
/// nil shows every row.
struct CSVGridView: View {
    struct Row: Identifiable {
        let id: String
        let cells: [String]
    }

    let header: [String]
    let rows: [Row]
    var visibleRowCount: Int?

    private static let lineWidth: CGFloat = 1

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: Self.lineWidth, verticalSpacing: Self.lineWidth) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, title in
                        cell(title)
                            .fontWeight(.semibold)
                            .foregroundStyle(.tint)
                            .background(Color("GridHeaderFill"))
                    }
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    let isVisible = visibleRowCount.map { index < $0 } ?? true
                    GridRow {
                        ForEach(Array(row.cells.enumerated()), id: \.offset) { _, value in
                            cell(value, isVisible: isVisible)
                                .background(Color(uiColor: .secondarySystemGroupedBackground))
                        }
                    }
                }
            }
            .padding(Self.lineWidth)
            .background(Color("GridLine"))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private func cell(_ text: String, isVisible: Bool = true) -> some View {
        Text(text.isEmpty ? " " : text)
            .font(.footnote)
            .fontDesign(.monospaced)
            .lineLimit(1)
            .fixedSize()
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 4)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
