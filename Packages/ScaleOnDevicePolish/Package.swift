// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScaleOnDevicePolish",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(name: "ScaleOnDevicePolish", targets: ["ScaleOnDevicePolish"]),
    ],
    targets: [
        // Path-based so Xcode does not depend on DerivedData SPM artifact extraction
        // (remote binaryTarget vanished whenever disk was full / caches reset).
        // Populate with: ./scripts/fetch-llama.sh
        .binaryTarget(
            name: "llama",
            path: "Vendor/llama.xcframework"
        ),
        .target(
            name: "ScaleOnDevicePolish",
            dependencies: ["llama"],
            path: "Sources/ScaleOnDevicePolish"
        ),
        .testTarget(
            name: "ScaleOnDevicePolishTests",
            dependencies: ["ScaleOnDevicePolish"],
            path: "Tests/ScaleOnDevicePolishTests"
        ),
    ]
)
