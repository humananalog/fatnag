import Foundation

/// Shipped polish model identity. Weights download on eligible devices only.
public enum OnDevicePolishCatalog: Sendable {
    public static let modelID = "qwen2.5-0.5b-instruct-q4_k_m"
    public static let displayName = "On-device polish (0.5B)"
    public static let filename = "qwen2.5-0.5b-instruct-q4_k_m.gguf"
    /// Hugging Face GGUF. Host may override via `OnDevicePolishInstaller.Configuration`.
    public static let defaultDownloadURL = URL(
        string: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf"
    )!
    /// Approx payload from HF `x-linked-size` (bytes).
    public static let expectedByteCount: Int64 = 491_400_032
    public static let minimumPhysicalMemoryBytes: UInt64 = 3_500_000_000
    public static let packageVersion = "1.0.0"
}
