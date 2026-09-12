import Foundation
import SwiftUI

/// Stable band vs the most recent HealthKit body-mass sample.
///
/// Threshold: ±0.2 kg. Smaller deltas count as stable (daily noise / hydration).
enum WeightTrend: Equatable, Sendable {
    static let stableThresholdKg: Double = 0.2

    case loss(deltaKg: Double)
    case stable(deltaKg: Double)
    case gain(deltaKg: Double)
    case unknown

    var deltaKg: Double? {
        switch self {
        case .loss(let d), .stable(let d), .gain(let d):
            return d
        case .unknown:
            return nil
        }
    }

    var title: String {
        switch self {
        case .loss:
            return "Down"
        case .stable:
            return "Stable"
        case .gain:
            return "Up"
        case .unknown:
            return "No baseline"
        }
    }

    /// Compact chip label so the top-right pill never truncates mid-word on iPhone 15.
    var shortTitle: String {
        switch self {
        case .loss:
            return "Down"
        case .stable:
            return "Stable"
        case .gain:
            return "Up"
        case .unknown:
            return "No base"
        }
    }

    var subtitle: String {
        switch self {
        case .loss(let d):
            return String(format: "%.2f kg below last Health weight", abs(d))
        case .stable(let d):
            return String(format: "Within ±%.1f kg of last Health weight (Δ %.2f)", Self.stableThresholdKg, d)
        case .gain(let d):
            return String(format: "%.2f kg above last Health weight", abs(d))
        case .unknown:
            return "Connect Apple Health to compare against prior weights"
        }
    }

    static func from(currentKg: Double, baselineKg: Double?) -> WeightTrend {
        guard let baselineKg else { return .unknown }
        let delta = currentKg - baselineKg
        if delta <= -stableThresholdKg {
            return .loss(deltaKg: delta)
        }
        if delta >= stableThresholdKg {
            return .gain(deltaKg: delta)
        }
        return .stable(deltaKg: delta)
    }
}

/// Soft atmosphere colors for the full-screen weigh-in sheet (light, calm, not neon).
struct TrendAtmosphere: Equatable {
    let top: Color
    let mid: Color
    let bottom: Color
    let accent: Color

    static func forTrend(_ trend: WeightTrend) -> TrendAtmosphere {
        switch trend {
        case .loss:
            // Soft sage / mint: weight loss
            return TrendAtmosphere(
                top: Color(red: 0.78, green: 0.92, blue: 0.84),
                mid: Color(red: 0.55, green: 0.78, blue: 0.66),
                bottom: Color(red: 0.32, green: 0.58, blue: 0.48),
                accent: Color(red: 0.12, green: 0.42, blue: 0.32)
            )
        case .stable:
            // Soft amber / gold: stable (not terracotta cream cliché)
            return TrendAtmosphere(
                top: Color(red: 0.98, green: 0.93, blue: 0.78),
                mid: Color(red: 0.94, green: 0.82, blue: 0.42),
                bottom: Color(red: 0.82, green: 0.62, blue: 0.18),
                accent: Color(red: 0.45, green: 0.32, blue: 0.05)
            )
        case .gain:
            // Soft coral / rose: gain
            return TrendAtmosphere(
                top: Color(red: 0.98, green: 0.86, blue: 0.84),
                mid: Color(red: 0.92, green: 0.58, blue: 0.52),
                bottom: Color(red: 0.78, green: 0.32, blue: 0.30),
                accent: Color(red: 0.48, green: 0.12, blue: 0.12)
            )
        case .unknown:
            // Cool stone / sky: no baseline yet
            return TrendAtmosphere(
                top: Color(red: 0.90, green: 0.93, blue: 0.96),
                mid: Color(red: 0.72, green: 0.80, blue: 0.88),
                bottom: Color(red: 0.42, green: 0.52, blue: 0.62),
                accent: Color(red: 0.18, green: 0.24, blue: 0.32)
            )
        }
    }
}

/// Recent HealthKit body-mass sample used as trend baseline.
struct HealthWeightSample: Equatable, Identifiable, Sendable {
    let id: UUID
    let weightKg: Double
    let date: Date

    init(id: UUID = UUID(), weightKg: Double, date: Date) {
        self.id = id
        self.weightKg = weightKg
        self.date = date
    }
}
