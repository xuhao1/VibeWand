// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VibeWand",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AU05Device", targets: ["AU05Device"]),
        .executable(name: "AU05Capture", targets: ["AU05Capture"]),
        .executable(name: "VibeWand", targets: ["VibeKeyBridge"])
    ],
    targets: [
        .target(name: "AU05Device"),
        .executableTarget(name: "AU05Capture", dependencies: ["AU05Device"]),
        .executableTarget(name: "VibeKeyBridge", dependencies: ["AU05Device"]),
        .testTarget(name: "AU05DeviceTests", dependencies: ["AU05Device"]),
        .testTarget(name: "VibeKeyBridgeTests", dependencies: ["VibeKeyBridge"])
    ]
)
