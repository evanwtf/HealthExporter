import SwiftUI

@main
struct HealthExporterApp: App {
    @StateObject private var settings = SettingsManager()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                LaunchView(settings: settings)
            }
            .tint(.accentColor)
        }
    }
}
