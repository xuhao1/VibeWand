// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VibeWand",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "SpeechInput", targets: ["SpeechInput"]),
        .executable(name: "SpeechAPICheck", targets: ["SpeechAPICheck"]),
        .library(name: "AU05Device", targets: ["AU05Device"]),
        .library(name: "WandAgent", targets: ["WandAgent"]),
        .library(name: "InputLink", targets: ["InputLink"]),
        .executable(name: "VibeWandInput", targets: ["VibeWandInput"]),
        .executable(name: "AU05Capture", targets: ["AU05Capture"]),
        .executable(name: "VibeWand", targets: ["VibeKeyBridge"])
    ],
    targets: [
        .target(name: "SpeechInput"),
        .executableTarget(name: "SpeechAPICheck", dependencies: ["SpeechInput"]),
        .target(name: "AU05Device"),
        .executableTarget(name: "AU05Capture", dependencies: ["AU05Device"]),
        .target(name: "WandAgent"),
        .target(name: "InputLink"),
        .executableTarget(name: "VibeWandInput", dependencies: ["InputLink"]),
        .executableTarget(name: "VibeKeyBridge", dependencies: ["AU05Device", "SpeechInput", "WandAgent", "InputLink"]),
        .testTarget(name: "SpeechInputTests", dependencies: ["SpeechInput"]),
        .testTarget(name: "AU05DeviceTests", dependencies: ["AU05Device"]),
        .testTarget(name: "WandAgentTests", dependencies: ["WandAgent"]),
        .testTarget(name: "InputLinkTests", dependencies: ["InputLink"]),
        .testTarget(name: "VibeKeyBridgeTests", dependencies: ["VibeKeyBridge", "InputLink"])
    ]
)
