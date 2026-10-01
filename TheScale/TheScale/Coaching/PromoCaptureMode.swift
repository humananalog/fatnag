import Foundation

#if DEBUG
/// Set when `-promoShot=` is present so Simulator captures skip permission sheets.
enum PromoCaptureMode {
    private static let key = "thescale.promoCapture.active"

    static var isActive: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func activateIfNeeded(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let hasShot = arguments.contains(where: { $0.hasPrefix("-promoShot=") || $0 == "-promoShot" })
        isActive = hasShot
    }
}
#endif
