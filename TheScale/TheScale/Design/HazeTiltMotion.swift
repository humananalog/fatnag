import CoreMotion
import SwiftUI

/// Device-tilt spring for home haze layers. Shared so Weigh + Progress tabs
/// do not run two `CMMotionManager`s. Start/stop via retain count + scene phase.
@MainActor
final class HazeTiltMotion: ObservableObject {
    static let shared = HazeTiltMotion()

    /// Smoothed parallax offset in points (applied per haze layer with depth).
    @Published private(set) var offset: CGSize = .zero

    private let manager = CMMotionManager()
    private var clients = 0
    private var active = false

    private var positionX = 0.0
    private var positionY = 0.0
    private var velocityX = 0.0
    private var velocityY = 0.0
    private var targetX = 0.0
    private var targetY = 0.0
    private var lastTimestamp: TimeInterval?

    /// Soft spring: inertia without frantic bounce.
    private let stiffness = 18.0
    private let damping = 9.5
    /// Max travel from gravity (~±1).
    private let amplitude = 36.0

    private init() {}

    func retain() {
        clients += 1
        if clients == 1 {
            start()
        }
    }

    func release() {
        clients = max(0, clients - 1)
        if clients == 0 {
            stop()
            resetPhysics()
        }
    }

    private func start() {
        guard !active else { return }
        guard manager.isDeviceMotionAvailable else { return }

        active = true
        // Defer one runloop tick so CoreMotion does not race Managed Preferences
        // reads during cold launch (harmless sandbox warning otherwise).
        Task { @MainActor [weak self] in
            guard let self, self.active, self.clients > 0 else { return }
            self.manager.deviceMotionUpdateInterval = 1.0 / 10.0
            let queue = OperationQueue()
            queue.name = "com.humananalog.thescale.haze-tilt"
            queue.maxConcurrentOperationCount = 1
            self.manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] data, _ in
                guard let data else { return }
                // Integrate on the motion queue; hop to MainActor only to publish.
                Task { @MainActor [weak self] in
                    self?.integrate(data)
                }
            }
        }
    }

    private func stop() {
        guard active else { return }
        active = false
        manager.stopDeviceMotionUpdates()
        lastTimestamp = nil
    }

    private func resetPhysics() {
        positionX = 0
        positionY = 0
        velocityX = 0
        velocityY = 0
        targetX = 0
        targetY = 0
        if offset != .zero {
            offset = .zero
        }
    }

    private func integrate(_ data: CMDeviceMotion) {
        // Gravity: phone tilt maps to soft haze drift (not 1:1 snap).
        targetX = data.gravity.x * amplitude
        targetY = (-data.gravity.y) * amplitude

        let now = data.timestamp
        let dt: Double
        if let last = lastTimestamp {
            dt = min(max(now - last, 1.0 / 120.0), 1.0 / 15.0)
        } else {
            dt = 1.0 / 30.0
        }
        lastTimestamp = now

        // Critically-ish damped spring → inertia / settle.
        let ax = stiffness * (targetX - positionX) - damping * velocityX
        let ay = stiffness * (targetY - positionY) - damping * velocityY
        velocityX += ax * dt
        velocityY += ay * dt
        positionX += velocityX * dt
        positionY += velocityY * dt

        let next = CGSize(width: positionX, height: positionY)
        // Coarser publish threshold → fewer SwiftUI invalidations on A16.
        if abs(next.width - offset.width) > 0.45 || abs(next.height - offset.height) > 0.45 {
            offset = next
        }
    }
}
