import Foundation
import HealthKit
import os

/// Registers `HKObserverQuery` + `enableBackgroundDelivery` so Health updates can wake
/// The Scale without the user opening the app. iOS still throttles delivery; this wiring is real.
final class HealthKitBackgroundDelivery: @unchecked Sendable {
    static let shared = HealthKitBackgroundDelivery()

    private let log = Logger(subsystem: "app.thescale.ios", category: "HealthKitBackground")
    private let store = HKHealthStore()
    private let state = OSAllocatedUnfairLock(initialState: State())
    /// Minimum spacing between observer-driven wakes (coalesce bursty step/HR writes).
    private let coalesceSeconds: TimeInterval = 45

    private struct State {
        var observers: [HKObserverQuery] = []
        var isStarted = false
        var lastWakeAt: Date?
    }

    /// Invoked on a background queue when HealthKit delivers an update (or BG task asks for a sweep).
    var onHealthUpdate: (@Sendable (HealthKitBackgroundWakeReason) async -> Void)?

    enum HealthKitBackgroundWakeReason: String, Sendable {
        case workout
        case steps
        case sleep
        case heart
        case hrv
        case bodyMass
        case activeEnergy
        case processingTask
        case appRefresh
        case manual
    }

    private struct ObservedType {
        let type: HKSampleType
        let frequency: HKUpdateFrequency
        let reason: HealthKitBackgroundWakeReason
    }

    private var observedTypes: [ObservedType] {
        var items: [ObservedType] = []
        if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            // Apple enforces hourly minimum for step count background delivery.
            items.append(.init(type: steps, frequency: .hourly, reason: .steps))
        }
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            items.append(.init(type: energy, frequency: .hourly, reason: .activeEnergy))
        }
        if let hr = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            items.append(.init(type: hr, frequency: .hourly, reason: .heart))
        }
        if let hrv = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            items.append(.init(type: hrv, frequency: .hourly, reason: .hrv))
        }
        if let rhr = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            items.append(.init(type: rhr, frequency: .hourly, reason: .heart))
        }
        if let mass = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
            items.append(.init(type: mass, frequency: .immediate, reason: .bodyMass))
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            items.append(.init(type: sleep, frequency: .immediate, reason: .sleep))
        }
        items.append(.init(type: HKObjectType.workoutType(), frequency: .immediate, reason: .workout))
        return items
    }

    /// Enable background delivery + start observer queries. Safe to call repeatedly.
    func start() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let already = state.withLock { $0.isStarted }
        if already {
            await enableAllDeliveries()
            return
        }

        await enableAllDeliveries()
        startObserverQueries()

        state.withLock { $0.isStarted = true }
        log.info("HealthKit background delivery started for \(self.observedTypes.count, privacy: .public) types")
    }

    func stop() {
        let queries = state.withLock { state -> [HKObserverQuery] in
            let q = state.observers
            state.observers = []
            state.isStarted = false
            return q
        }
        for query in queries {
            store.stop(query)
        }
        store.disableAllBackgroundDelivery { _, _ in }
        log.info("HealthKit background delivery stopped")
    }

    /// Status line for Settings.
    func statusLine() -> String {
        let snapshot = state.withLock { ($0.isStarted, $0.observers.count, $0.lastWakeAt) }
        guard snapshot.0 else {
            return "Health background: not armed (open app once after Health access)."
        }
        let lastText: String = {
            guard let last = snapshot.2 else { return "no wake yet" }
            return "last wake \(last.formatted(date: .omitted, time: .shortened))"
        }()
        return "Health background: \(snapshot.1) observers · \(lastText). iOS throttles; not instant."
    }

    private func enableAllDeliveries() async {
        for item in observedTypes {
            do {
                try await store.enableBackgroundDelivery(for: item.type, frequency: item.frequency)
                log.debug("Enabled background delivery \(item.reason.rawValue, privacy: .public)")
            } catch {
                log.error(
                    "enableBackgroundDelivery failed \(item.reason.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private func startObserverQueries() {
        let previous = state.withLock { state -> [HKObserverQuery] in
            let q = state.observers
            state.observers = []
            return q
        }
        for query in previous {
            store.stop(query)
        }

        for item in observedTypes {
            let reason = item.reason
            let query = HKObserverQuery(sampleType: item.type, predicate: nil) {
                [weak self] _, completionHandler, error in
                if let error {
                    self?.log.error(
                        "Observer \(reason.rawValue, privacy: .public) error: \(error.localizedDescription, privacy: .public)"
                    )
                    completionHandler()
                    return
                }
                Task { [weak self] in
                    await self?.handleObserverFire(reason: reason)
                    completionHandler()
                }
            }
            store.execute(query)
            state.withLock { $0.observers.append(query) }
        }
    }

    private func handleObserverFire(reason: HealthKitBackgroundWakeReason) async {
        let shouldSkip = state.withLock { state -> Bool in
            if let last = state.lastWakeAt, Date().timeIntervalSince(last) < coalesceSeconds {
                return true
            }
            state.lastWakeAt = Date()
            return false
        }
        if shouldSkip {
            log.debug("Coalesced observer wake \(reason.rawValue, privacy: .public)")
            return
        }

        log.info("HealthKit observer wake: \(reason.rawValue, privacy: .public)")
        await onHealthUpdate?(reason)
    }

    /// Called from BGAppRefresh / BGProcessing without a specific sample type.
    func handleTaskWake(reason: HealthKitBackgroundWakeReason) async {
        state.withLock { $0.lastWakeAt = Date() }
        await onHealthUpdate?(reason)
    }
}
