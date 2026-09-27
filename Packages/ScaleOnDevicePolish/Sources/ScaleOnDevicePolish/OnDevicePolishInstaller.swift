import Foundation
import Network

/// Downloads and verifies the GGUF into Application Support. Never runs on Apple Intelligence phones.
@MainActor
public final class OnDevicePolishInstaller: ObservableObject {
    public struct Configuration: Sendable {
        public var downloadURL: URL
        public var preferWiFi: Bool
        public var allowsCellular: Bool

        public init(
            downloadURL: URL = OnDevicePolishCatalog.defaultDownloadURL,
            preferWiFi: Bool = true,
            allowsCellular: Bool = false
        ) {
            self.downloadURL = downloadURL
            self.preferWiFi = preferWiFi
            self.allowsCellular = allowsCellular
        }
    }

    public static let shared = OnDevicePolishInstaller()

    @Published public private(set) var snapshot = OnDevicePolishSnapshot(phase: .needsInstall)

    private var configuration = Configuration()
    private var appleIntelligenceDeviceCapable = true
    private var downloadTask: URLSessionDownloadTask?
    private var session: URLSession?
    private let fileManager = FileManager.default

    public var modelFileURL: URL {
        modelsDirectory.appendingPathComponent(OnDevicePolishCatalog.filename, isDirectory: false)
    }

    public var modelsDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("ScaleOnDevicePolish", isDirectory: true)
    }

    public func configure(
        appleIntelligenceDeviceCapable: Bool,
        configuration: Configuration = Configuration()
    ) {
        self.appleIntelligenceDeviceCapable = appleIntelligenceDeviceCapable
        self.configuration = configuration
        refreshSnapshot()
    }

    public func refreshSnapshot() {
        let policy = OnDevicePolishEligibility.policy(
            appleIntelligenceDeviceCapable: appleIntelligenceDeviceCapable
        )
        switch policy {
        case .appleIntelligenceDevice:
            snapshot = OnDevicePolishSnapshot(
                phase: .notApplicable(reason: "This iPhone uses Apple Intelligence. Sidecar not installed.")
            )
            return
        case .unsupported(let reason):
            snapshot = OnDevicePolishSnapshot(phase: .notApplicable(reason: reason))
            return
        case .installSidecar:
            break
        }

        if isModelPresent {
            let bytes = (try? fileManager.attributesOfItem(atPath: modelFileURL.path)[.size] as? NSNumber)?.int64Value ?? 0
            snapshot = OnDevicePolishSnapshot(phase: .ready, localBytes: bytes)
            return
        }

        if case .downloading = snapshot.phase {
            return
        }
        snapshot = OnDevicePolishSnapshot(phase: .needsInstall)
    }

    public var isModelPresent: Bool {
        guard fileManager.fileExists(atPath: modelFileURL.path) else { return false }
        let bytes = (try? fileManager.attributesOfItem(atPath: modelFileURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        // Accept ≥ 90% of catalog size (HF may re-pack slightly).
        return bytes >= (OnDevicePolishCatalog.expectedByteCount * 9) / 10
    }

    /// Auto path for compatible phones. No-op on Apple Intelligence hardware.
    public func ensureInstalledIfEligible() async {
        refreshSnapshot()
        guard OnDevicePolishEligibility.shouldAutoInstall(
            appleIntelligenceDeviceCapable: appleIntelligenceDeviceCapable
        ) else { return }
        guard !isModelPresent else {
            refreshSnapshot()
            return
        }
        if configuration.preferWiFi, !(await isExpensivePathAllowed()) {
            // Wait for better path; leave needsInstall so Settings can retry.
            snapshot = OnDevicePolishSnapshot(
                phase: .failed(message: "Waiting for Wi-Fi to download on-device polish (~470 MB).")
            )
            return
        }
        await startDownload()
    }

    public func startDownload() async {
        refreshSnapshot()
        guard case .installSidecar = OnDevicePolishEligibility.policy(
            appleIntelligenceDeviceCapable: appleIntelligenceDeviceCapable
        ) else { return }
        guard !isModelPresent else {
            refreshSnapshot()
            return
        }

        try? fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        snapshot = OnDevicePolishSnapshot(phase: .downloading(progress: 0))

        let delegate = DownloadDelegate { [weak self] progress in
            Task { @MainActor in
                self?.snapshot = OnDevicePolishSnapshot(phase: .downloading(progress: progress))
            }
        } completion: { [weak self] result in
            Task { @MainActor in
                await self?.finishDownload(result)
            }
        }

        let config = URLSessionConfiguration.default
        config.allowsCellularAccess = configuration.allowsCellular
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 60 * 60
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        self.session = session
        let task = session.downloadTask(with: configuration.downloadURL)
        downloadTask = task
        task.resume()
    }

    public func removeInstalledModel() throws {
        if fileManager.fileExists(atPath: modelFileURL.path) {
            try fileManager.removeItem(at: modelFileURL)
        }
        refreshSnapshot()
    }

    private func finishDownload(_ result: Result<URL, Error>) async {
        downloadTask = nil
        session?.finishTasksAndInvalidate()
        session = nil
        switch result {
        case .failure(let error):
            snapshot = OnDevicePolishSnapshot(
                phase: .failed(message: "Download failed: \(error.localizedDescription)")
            )
        case .success(let tempURL):
            snapshot = OnDevicePolishSnapshot(phase: .installing)
            do {
                if fileManager.fileExists(atPath: modelFileURL.path) {
                    try fileManager.removeItem(at: modelFileURL)
                }
                try fileManager.moveItem(at: tempURL, to: modelFileURL)
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                var url = modelFileURL
                try url.setResourceValues(values)
                refreshSnapshot()
            } catch {
                snapshot = OnDevicePolishSnapshot(
                    phase: .failed(message: "Install failed: \(error.localizedDescription)")
                )
            }
        }
    }

    private func isExpensivePathAllowed() async -> Bool {
        let allowsCellular = configuration.allowsCellular
        return await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "app.thescale.ondevice-polish.path")
            monitor.pathUpdateHandler = { path in
                monitor.cancel()
                if allowsCellular {
                    continuation.resume(returning: path.status == .satisfied)
                    return
                }
                let ok = path.status == .satisfied && !path.isExpensive && !path.isConstrained
                continuation.resume(returning: ok)
            }
            monitor.start(queue: queue)
        }
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private let onCompletion: @Sendable (Result<URL, Error>) -> Void

    init(
        onProgress: @escaping @Sendable (Double) -> Void,
        completion: @escaping @Sendable (Result<URL, Error>) -> Void
    ) {
        self.onProgress = onProgress
        self.onCompletion = completion
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let expected = totalBytesExpectedToWrite > 0
            ? totalBytesExpectedToWrite
            : OnDevicePolishCatalog.expectedByteCount
        let progress = min(0.99, Double(totalBytesWritten) / Double(max(expected, 1)))
        onProgress(progress)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("scale-polish-\(UUID().uuidString).gguf")
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: location, to: dest)
            onCompletion(.success(dest))
        } catch {
            onCompletion(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            onCompletion(.failure(error))
        }
    }
}
