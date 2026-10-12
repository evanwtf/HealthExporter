import SwiftUI

extension View {
    /// Section header type role: SF Pro Expanded semibold, sentence case.
    func sectionHeaderStyle() -> some View {
        self
            .font(.subheadline.weight(.semibold))
            .fontWidth(.expanded)
            .foregroundStyle(.primary)
            .textCase(nil)
    }
}
