// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "vibepilot",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "VibeCore", path: "Sources/VibeCore"),
        .executableTarget(name: "vibepilot", dependencies: ["VibeCore"], path: "Sources/vibepilot"),
        .executableTarget(name: "vibeapp", dependencies: ["VibeCore"], path: "Sources/vibeapp")
    ]
)
