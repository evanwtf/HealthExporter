import SwiftUI
import UIKit
import XCTest
@testable import HealthExporter

/// Renders each screen in light and dark mode and attaches the PNGs to the
/// test result. A rendering harness for review, not a pixel comparison.
///
/// The class is `nonisolated` because `XCTestCase` is: a main-actor subclass
/// would change the isolation of its initializers. XCTest runs each test
/// method on the main thread, so the methods that touch UI are `@MainActor`.
nonisolated final class ScreenshotTests: XCTestCase {
    private static let windowSize = CGSize(width: 402, height: 874)
    private static let scale: CGFloat = 3

    /// Computed, so the non-Sendable `[String: Any]` is never shared state.
    private static var seededKeys: [String: Any] {
        [
            "exportWeight": true,
            "exportSteps": true,
            "exportGlucose": true,
            "selectedLabPanels": [LabPanel.lipid.rawValue],
            "favoriteLabCodes": [LOINCCode.hemoglobinA1C],
            "expandedLabPanels": [LabPanel.lipid.rawValue],
            "selectedVitalMetrics": [String](),
            "expandedVitalsSection": false,
        ]
    }

    @MainActor private static var settings: SettingsManager?
    private var savedValues: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        for (key, value) in Self.seededKeys {
            if let old = defaults.object(forKey: key) {
                savedValues[key] = old
            }
            defaults.set(value, forKey: key)
        }
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        for key in Self.seededKeys.keys {
            if let old = savedValues[key] {
                defaults.set(old, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        super.tearDown()
    }

    /// One shared instance: the seeded defaults are read once, at init.
    @MainActor private func sharedSettings() -> SettingsManager {
        if let settings = Self.settings { return settings }
        let settings = SettingsManager()
        Self.settings = settings
        return settings
    }

    @MainActor func testLaunchView() {
        let settings = sharedSettings()
        capture("01-launch") {
            NavigationStack {
                LaunchView(settings: settings)
            }
        }
    }

    @MainActor func testDataSelectionView() {
        let settings = sharedSettings()
        capture("02-data-selection") {
            NavigationStack {
                DataSelectionView(settings: settings)
            }
        }
    }

    @MainActor func testSettingsView() {
        let settings = sharedSettings()
        capture("03-settings") {
            SettingsView(settings: settings)
        }
    }

    @MainActor func testLargeTypeLaunchView() {
        let settings = sharedSettings()
        capture("05-launch-large-type") {
            NavigationStack {
                LaunchView(settings: settings)
            }
            .environment(\.dynamicTypeSize, .accessibility2)
        }
    }

    @MainActor func testLargeTypeDataSelectionView() {
        let settings = sharedSettings()
        capture("06-data-selection-large-type") {
            NavigationStack {
                DataSelectionView(settings: settings)
            }
            .environment(\.dynamicTypeSize, .accessibility2)
        }
    }

    @MainActor func testNothingSelectedDataSelectionView() {
        let settings = sharedSettings()
        let saved = (settings.exportWeight, settings.exportSteps, settings.exportGlucose,
                     settings.selectedLabPanels, settings.favoriteLabCodes)
        settings.exportWeight = false
        settings.exportSteps = false
        settings.exportGlucose = false
        settings.selectedLabPanels = []
        settings.favoriteLabCodes = []
        defer {
            (settings.exportWeight, settings.exportSteps, settings.exportGlucose,
             settings.selectedLabPanels, settings.favoriteLabCodes) = saved
        }
        capture("07-data-selection-nothing-selected") {
            NavigationStack {
                DataSelectionView(settings: settings)
            }
        }
    }

    @MainActor func testMixedSelectionDataSelectionView() {
        let settings = sharedSettings()
        let saved = (settings.exportWeight, settings.exportSteps, settings.exportGlucose,
                     settings.selectedLabPanels, settings.favoriteLabCodes, settings.selectedVitalMetrics)
        settings.exportWeight = true
        settings.exportSteps = false
        settings.exportGlucose = true
        settings.selectedLabPanels = [.lipid, .thyroid]
        settings.favoriteLabCodes = [LOINCCode.hemoglobinA1C]
        settings.selectedVitalMetrics = [.bloodPressure, .restingHeartRate]
        defer {
            (settings.exportWeight, settings.exportSteps, settings.exportGlucose,
             settings.selectedLabPanels, settings.favoriteLabCodes, settings.selectedVitalMetrics) = saved
        }
        capture("08-data-selection-mixed") {
            NavigationStack {
                DataSelectionView(settings: settings)
            }
        }
    }

    @MainActor func testLabPanelDetailView() {
        let settings = sharedSettings()
        capture("09-lab-panel-detail") {
            NavigationStack {
                DataSelectionView(settings: settings).labPanelDetail(.other)
            }
        }
    }

    @MainActor func testPrivacyPolicyView() {
        capture("04-privacy") {
            NavigationStack {
                PrivacyPolicyView()
            }
        }
    }

    @MainActor private func capture<Content: View>(_ name: String, @ViewBuilder content: () -> Content) {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let suffix = style == .dark ? "dark" : "light"
            let image = render(content(), style: style)
            XCTAssertGreaterThan(image.size.width, 0, "\(name)-\(suffix)")
            XCTAssertGreaterThan(image.size.height, 0, "\(name)-\(suffix)")
            XCTAssertNotNil(image.pngData(), "\(name)-\(suffix)")

            let attachment = XCTAttachment(image: image)
            attachment.name = "\(name)-\(suffix)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor private func render<Content: View>(_ view: Content, style: UIUserInterfaceStyle) -> UIImage {
        let frame = CGRect(origin: .zero, size: Self.windowSize)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            XCTFail("The test host has no window scene")
            return UIImage()
        }
        let window = UIWindow(windowScene: scene)
        window.frame = frame
        window.overrideUserInterfaceStyle = style
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))

        let format = UIGraphicsImageRendererFormat()
        format.scale = Self.scale
        let image = UIGraphicsImageRenderer(bounds: frame, format: format).image { _ in
            window.drawHierarchy(in: frame, afterScreenUpdates: true)
        }
        window.isHidden = true
        window.rootViewController = nil
        return image
    }
}
