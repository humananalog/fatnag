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
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b5046/llama-b5046-xcframework.zip",
            checksum: "c19be78b5f00d8d29a25da41042cb7afa094cbf6280a225abe614b03b20029ab"
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
