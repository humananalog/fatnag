import Foundation

/// DEBUG console helper. Release builds compile to no-ops.
/// Throttle keys so Health observer / scene-active wakes cannot flood Xcode Console
/// with identical Home-gauge / FitnessDigest lines.
enum ScaleDebugLog {
    private static let lock = NSLock()
    private static var lastPrintedAt: [String: Date] = [:]

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
        lock.lock()
        let now = Date()
        if let last = lastPrintedAt[key], now.timeIntervalSince(last) < interval {
            lock.unlock()
            return
        }
        lastPrintedAt[key] = now
        lock.unlock()
        Swift.print("[TheScale] \(message())")
        #endif
    }

    #if DEBUG
    /// Test / DEBUG reset only.
    static func resetThrottleStateForTests() {
        lock.lock()
        lastPrintedAt.removeAll()
        lock.unlock()
    }
    #endif
}
