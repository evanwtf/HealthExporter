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
        case .weight: return "Weight"
        case .steps: return "Steps"
        case .glucose: return "Blood Glucose"
        case .vitals: return "Vitals"
        case .labs: return "Lab results"
        }
    }

    var systemImage: String {
        switch self {
        case .weight: return "scalemass.fill"
        case .steps: return "figure.walk"
        case .glucose: return "drop.fill"
        case .vitals: return "heart.fill"
        case .labs: return "list.clipboard.fill"
        }
    }

    var color: Color {
        switch self {
        case .weight: return Color("CategoryWeight")
        case .steps: return Color("CategorySteps")
        case .glucose: return Color("CategoryGlucose")
        case .vitals: return Color("CategoryVitals")
        case .labs: return Color("CategoryLabs")
        }
    }
}
