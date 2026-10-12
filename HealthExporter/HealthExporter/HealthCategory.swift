import SwiftUI

/// Apple Health categories the app exports, with Health's color and glyph.
/// The colors are darker than the system colors so white text on a filled
/// tile keeps a contrast ratio of at least 4.5:1 in light and dark mode.
enum HealthCategory: CaseIterable {
    case weight
    case steps
    case glucose
    case vitals
    case labs

    var name: String {
        switch self {
        case .weight: "Weight"
        case .steps: "Steps"
        case .glucose: "Blood Glucose"
        case .vitals: "Vitals"
        case .labs: "Lab results"
        }
    }

    var systemImage: String {
        switch self {
        case .weight: "scalemass.fill"
        case .steps: "figure.walk"
        case .glucose: "drop.fill"
        case .vitals: "heart.fill"
        case .labs: "list.clipboard.fill"
        }
    }

    var color: Color {
        switch self {
        case .weight: Color("CategoryWeight")
        case .steps: Color("CategorySteps")
        case .glucose: Color("CategoryGlucose")
        case .vitals: Color("CategoryVitals")
        case .labs: Color("CategoryLabs")
        }
    }
}
