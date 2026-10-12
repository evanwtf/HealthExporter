import Foundation

/// Configuration for supported health metrics.
nonisolated struct HealthMetricConfig: Sendable {
    let name: String
}

/// Centralized configuration for all health metrics
nonisolated enum HealthMetrics {
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
