import Foundation

/// Evidence that the user already has a smart scale (or scale app) writing weight into Apple Health.
struct HealthSyncedScaleSignal: Equatable, Sendable {
    /// True when Health mass samples look like a third-party scale sync, not Apple/FATNAG manual.
    var isLikely: Bool
    /// Best display name for Settings / onboarding copy (e.g. "Withings").
    var primarySourceName: String?
    /// Bundle id of that source when available.
    var primaryBundleId: String?

    static let none = HealthSyncedScaleSignal(isLikely: false, primarySourceName: nil, primaryBundleId: nil)
}

/// Classifies HealthKit body-mass sources so we can skip Bluetooth scale hunting.
enum HealthSyncedScaleDetector {
    /// Our own writes — never count as an external scale.
    static let ourBundleIds: Set<String> = [
        "app.thescale.ios",
        "app.thescale.ios.tests",
    ]

    /// Vendor tokens matched against lowercase source name or bundle id.
    static let knownScaleVendorTokens: [String] = [
        "withings",
        "renpho",
        "eufy",
        "fitbit",
        "garmin",
        "xiaomi",
        "huami",
        "zepp",
        "qardio",
        "wyze",
        "anker",
        "amazfit",
        "yolanda",
        "1byone",
        "etekcity",
        "greater goods",
        "greatergoods",
        "lefu",
        "arboleaf",
        "picooc",
        "omron",
        "body+",
        "bodyplus",
        "miscale",
        "mi scale",
        "mi fit",
        "zepp life",
        "smart scale",
        "smartscale",
        "iscale",
        "yunmai",
        "acozyfeel",
        "wahoofitness",
        "polar",
    ]

    /// Evaluate recent (newest-first or any order) Health weight samples.
    static func evaluate(
        samples: [HealthWeightSample],
        now: Date = Date(),
        calendar: Calendar = .current,
        ourBundles: Set<String> = ourBundleIds
    ) -> HealthSyncedScaleSignal {
        let windowStart = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let recentFreshCutoff = calendar.date(byAdding: .day, value: -21, to: now) ?? now

        let candidates = samples.filter { sample in
            guard sample.date >= windowStart else { return false }
            return classification(for: sample, ourBundles: ourBundles) != .ignored
        }

        guard !candidates.isEmpty else { return .none }

        // Prefer an explicit known scale vendor with at least one sample in the last 21 days.
        let knownFresh = candidates.filter { sample in
            classification(for: sample, ourBundles: ourBundles) == .knownVendor
                && sample.date >= recentFreshCutoff
        }
        if let best = preferredSource(in: knownFresh) {
            return HealthSyncedScaleSignal(
                isLikely: true,
                primarySourceName: best.sourceName?.nilIfBlank,
                primaryBundleId: best.sourceBundleId?.nilIfBlank
            )
        }

        // Otherwise: same foreign (non-Apple / non-FATNAG) source wrote ≥2 samples in 30 days,
        // and the newest is within 14 days — typical Health-synced scale cadence.
        let freshCutoff14 = calendar.date(byAdding: .day, value: -14, to: now) ?? now
        let foreign = candidates.filter { classification(for: $0, ourBundles: ourBundles) == .foreign }
        let grouped = Dictionary(grouping: foreign) { sourceKey(for: $0) }
        let recurring = grouped.values
            .filter { $0.count >= 2 }
            .filter { group in group.contains(where: { $0.date >= freshCutoff14 }) }
            .sorted { lhs, rhs in
                let lMax = lhs.map(\.date).max() ?? .distantPast
                let rMax = rhs.map(\.date).max() ?? .distantPast
                return lMax > rMax
            }
        if let bestGroup = recurring.first, let best = preferredSource(in: bestGroup) {
            return HealthSyncedScaleSignal(
                isLikely: true,
                primarySourceName: best.sourceName?.nilIfBlank,
                primaryBundleId: best.sourceBundleId?.nilIfBlank
            )
        }

        return .none
    }

    // MARK: - Internals

    private enum Kind {
        case ignored
        case knownVendor
        case foreign
    }

    private static func classification(for sample: HealthWeightSample, ourBundles: Set<String>) -> Kind {
        let bundle = (sample.sourceBundleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let name = (sample.sourceName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if bundle.isEmpty && name.isEmpty { return .ignored }
        if ourBundles.contains(where: { bundle == $0.lowercased() || bundle.hasPrefix($0.lowercased() + ".") }) {
            return .ignored
        }
        if bundle.hasPrefix("com.apple.") || bundle == "com.apple.health" {
            return .ignored
        }
        // Health app manual entry often shows name "Health" with Apple bundle.
        if name == "health" || name == "santé" || name == "salud" || name == "salute" {
            if bundle.isEmpty || bundle.hasPrefix("com.apple") { return .ignored }
        }

        let hay = bundle.isEmpty ? name : "\(bundle) \(name)"
        if knownScaleVendorTokens.contains(where: { hay.contains($0) }) {
            return .knownVendor
        }
        // Any other third-party writer can still qualify via recurrence.
        return .foreign
    }

    private static func sourceKey(for sample: HealthWeightSample) -> String {
        let bundle = (sample.sourceBundleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !bundle.isEmpty { return "b:\(bundle)" }
        let name = (sample.sourceName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "n:\(name)"
    }

    private static func preferredSource(in samples: [HealthWeightSample]) -> HealthWeightSample? {
        samples.max(by: { $0.date < $1.date })
    }
}

private extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
