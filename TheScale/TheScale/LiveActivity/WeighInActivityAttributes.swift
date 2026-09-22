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
