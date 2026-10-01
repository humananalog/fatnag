import ActivityKit
import Foundation

/// Live Activity + Dynamic Island for an in-progress weigh-in.
struct WeighInActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        var weightKg: Double?
        var statusLine: String
        var isSettled: Bool
    }

    var scaleName: String
    var startedAt: Date
}

/// Unchecked box: ActivityKit's Activity is not Sendable under Swift 6 yet.
private struct WeighInActivityBox: @unchecked Sendable {
    let activity: Activity<WeighInActivityAttributes>
}

/// Starts / updates / ends the weigh-in Live Activity (Dynamic Island + Lock Screen).
@MainActor
enum WeighInLiveActivityController {
    private static var boxed: WeighInActivityBox?

    static var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    static var isRunning: Bool { boxed != nil }

    static func start(scaleName: String, statusLine: String = "Listening…") {
        guard isSupported else { return }
        end()
        let attributes = WeighInActivityAttributes(
            scaleName: scaleName.isEmpty ? "Scale" : scaleName,
            startedAt: Date()
        )
        let state = WeighInActivityAttributes.ContentState(
            weightKg: nil,
            statusLine: statusLine,
            isSettled: false
        )
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: Date().addingTimeInterval(15 * 60)),
                pushType: nil
            )
            boxed = WeighInActivityBox(activity: activity)
            #if DEBUG
            print("[TheScale] Weigh-in Live Activity started")
            #endif
        } catch {
            #if DEBUG
            print("[TheScale] Live Activity start failed: \(error.localizedDescription)")
            #endif
        }
    }

    static func update(weightKg: Double?, statusLine: String, isSettled: Bool = false) {
        guard let boxed else { return }
        let state = WeighInActivityAttributes.ContentState(
            weightKg: weightKg,
            statusLine: statusLine,
            isSettled: isSettled
        )
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(10 * 60))
        let box = boxed
        Task {
            await box.activity.update(content)
        }
    }

    static func end() {
        guard let boxed else { return }
        let box = boxed
        Self.boxed = nil
        let kg = box.activity.content.state.weightKg
        Task {
            let final = WeighInActivityAttributes.ContentState(
                weightKg: kg,
                statusLine: "Done",
                isSettled: true
            )
            await box.activity.end(.init(state: final, staleDate: nil), dismissalPolicy: .immediate)
        }
    }
}

/// Dynamic Island LED while Keel is loading or caching. Pages stay interactive.
struct KeelIslandActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        var label: String
    }

    var startedAt: Date
}

private struct KeelIslandActivityBox: @unchecked Sendable {
    let activity: Activity<KeelIslandActivityAttributes>
}

@MainActor
enum KeelIslandActivityController {
    private static var boxed: KeelIslandActivityBox?
    private static var depth = 0
    private static var pending: Task<Void, Never>?

    /// Shows the island only if work is still going after a short beat, so fast cache hits stay quiet.
    static func begin(label: String) {
        depth += 1
        pending?.cancel()
        let captured = label
        pending = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled, depth > 0 else { return }
            guard !WeighInLiveActivityController.isRunning else { return }
            present(label: captured)
        }
    }

    static func end() {
        depth = max(0, depth - 1)
        guard depth == 0 else { return }
        pending?.cancel()
        pending = nil
        guard let boxed else { return }
        let box = boxed
        Self.boxed = nil
        Task {
            let final = KeelIslandActivityAttributes.ContentState(label: "Ready")
            await box.activity.end(.init(state: final, staleDate: nil), dismissalPolicy: .immediate)
        }
    }

    private static func present(label: String) {
        guard WeighInLiveActivityController.isSupported else { return }
        let state = KeelIslandActivityAttributes.ContentState(label: label)
        if let boxed {
            let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(15 * 60))
            Task { await boxed.activity.update(content) }
            return
        }
        let attributes = KeelIslandActivityAttributes(startedAt: Date())
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: Date().addingTimeInterval(15 * 60)),
                pushType: nil
            )
            boxed = KeelIslandActivityBox(activity: activity)
        } catch {
            #if DEBUG
            print("[TheScale] Keel island start failed: \(error.localizedDescription)")
            #endif
        }
    }
}
