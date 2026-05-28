import Foundation

/// Configuration for supported health metrics.
struct HealthMetricConfig {
    let name: String
}

/// Centralized configuration for all health metrics
enum HealthMetrics {
    static let weight = HealthMetricConfig(
        name: "Weight"
    )
    
    static let steps = HealthMetricConfig(
        name: "Steps"
    )
    
    static let glucose = HealthMetricConfig(
        name: "Blood Glucose"
    )
}
