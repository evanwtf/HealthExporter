import SwiftUI
import UIKit

@main
struct HealthExporterApp: App {
    @StateObject private var settings = SettingsManager()

    init() {
        Self.useRoundedNavigationTitles()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                LaunchView(settings: settings)
            }
            .tint(.accentColor)
        }
    }

    /// Navigation bar titles in bold SF Pro Rounded. The fonts come from the
    /// preferred text-style descriptors, so they follow Dynamic Type at launch.
    private static func useRoundedNavigationTitles() {
        let appearance = UINavigationBar.appearance()
        appearance.largeTitleTextAttributes = [.font: roundedBoldFont(.largeTitle)]
        appearance.titleTextAttributes = [.font: roundedBoldFont(.headline)]
    }

    private static func roundedBoldFont(_ style: UIFont.TextStyle) -> UIFont {
        var descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style)
        if let rounded = descriptor.withDesign(.rounded) {
            descriptor = rounded
        }
        if let bold = descriptor.withSymbolicTraits(.traitBold) {
            descriptor = bold
        }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
