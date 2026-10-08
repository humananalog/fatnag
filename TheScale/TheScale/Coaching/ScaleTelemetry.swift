import Foundation

/// Anonymous first-party product telemetry (no ad ID, no chat text, no Health samples).
/// Events go to the FATNAG telemetry Worker; admin dashboard is password-gated.
enum ScaleTelemetry {
    private static let endpointKey = "TelemetryURL"
    private static let defaultHost = "https://fatnag-telemetry.alexhuther.workers.dev"

    /// Soft opt-out. Default on — anonymous aggregates for product improvement.
    private static let enabledKey = "thescale.telemetry.enabled"

    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    private static var endpoint: URL? {
        let raw = (Bundle.main.object(forInfoDictionaryKey: endpointKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.isEmpty { return URL(string: defaultHost) }
        return URL(string: raw)
    }

    /// Fire-and-forget. Never blocks UI. Never includes message bodies.
    @MainActor
    static func track(_ name: String, props: [String: Any] = [:]) {
        guard isEnabled else { return }
        guard let endpoint else { return }
        guard let secret = GrokSharedConfig.appSecret, !secret.isEmpty else { return }

        let device = ScaleAnonymousIdentity.userId.uuidString
        let plan = ScaleSubscriptionStore.shared.plan.rawValue
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

        var safeProps: [String: Any] = [:]
        for (k, v) in props {
            switch v {
            case let s as String where s.count <= 64:
                safeProps[k] = s
            case let i as Int:
                safeProps[k] = i
            case let b as Bool:
                safeProps[k] = b
            case let d as Double:
                safeProps[k] = d
            default:
                break
            }
        }

        let payload: [String: Any] = [
            "name": String(name.prefix(64)),
            "ts": Int(Date().timeIntervalSince1970),
            "device_id": device,
            "plan": plan,
            "app_version": version,
            "app_build": build,
            "props": safeProps
        ]

        Task.detached(priority: .utility) {
            guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
            var request = URLRequest(url: endpoint.appendingPathComponent("v1/event"))
            request.httpMethod = "POST"
            request.timeoutInterval = 8
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(secret, forHTTPHeaderField: "X-Scale-App-Secret")
            request.setValue(device, forHTTPHeaderField: "X-Scale-Device-Id")
            request.httpBody = body
            _ = try? await URLSession.shared.data(for: request)
        }
    }
}
