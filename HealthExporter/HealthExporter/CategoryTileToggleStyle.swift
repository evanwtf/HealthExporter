import SwiftUI

/// Draws a toggle as an Apple Health category tile. Off: grouped background
/// with the glyph in the category color. On: filled with the category color,
/// white glyph and text. The label is the title; `detail` is the line below it.
struct CategoryTileToggleStyle: ToggleStyle {
    let category: HealthCategory
    let detail: String
    /// Space kept free at the trailing edge for an overlaid details button.
    var reservesTrailingAccessory = false

    /// Fixed, not scaled: at large sizes the text sets the height.
    private let minHeight: CGFloat = 112
    @ScaledMetric(relativeTo: .title2) private var accessoryWidth: CGFloat = 44
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let isOn = configuration.isOn
        return Button {
            configuration.isOn.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: category.systemImage)
                        .font(.title2)
                        .foregroundStyle(isOn ? Color.white : category.color)
                        .accessibilityHidden(true)
                    Spacer(minLength: 8)
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isOn ? Color.white : Color("SecondaryText"))
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 2) {
                    configuration.label
                        .font(.headline)
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(isOn ? Color.white : Color("SecondaryText"))
                        .monospacedDigit()
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, reservesTrailingAccessory ? accessoryWidth : 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity, alignment: .topLeading)
            .background(
                isOn ? category.color : Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? Text("On") : Text("Off"))
    }
}
