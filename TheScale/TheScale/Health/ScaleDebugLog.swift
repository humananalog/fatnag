import Foundation

/// DEBUG console helper. Release builds compile to no-ops.
/// Throttle keys so Health observer / scene-active wakes cannot flood Xcode Console
/// with identical Home-gauge / FitnessDigest lines.
enum ScaleDebugLog {
    private static let box = ThrottleBox()

    /// Default spacing between identical throttle keys (observer wakes + scene active).
    static let defaultInterval: TimeInterval = 45

    /// Print immediately in DEBUG; silent in Release.
    static func print(_ message: @autoclosure () -> String) {
        #if DEBUG
        Swift.print("[TheScale] \(message())")
        #endif
    }

    /// Print at most once per `interval` for a given `key` (DEBUG only).
    static func throttled(
        _ key: String,
        every interval: TimeInterval = defaultInterval,
        _ message: @autoclosure () -> String
    ) {
        #if DEBUG
        box.lock.lock()
        let now = Date()
        if let last = box.lastPrintedAt[key], now.timeIntervalSince(last) < interval {
            box.lock.unlock()
            return
        }
        box.lastPrintedAt[key] = now
        box.lock.unlock()
        Swift.print("[TheScale] \(message())")
        #endif
    }

    #if DEBUG
    /// Test / DEBUG reset only.
    static func resetThrottleStateForTests() {
        box.lock.lock()
        box.lastPrintedAt.removeAll()
        box.lock.unlock()
    }
    #endif
}

private final class ThrottleBox: @unchecked Sendable {
    let lock = NSLock()
    var lastPrintedAt: [String: Date] = [:]
}
