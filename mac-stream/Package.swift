// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "vibework",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "VibeCore", path: "Sources/VibeCore"),
        .executableTarget(name: "vibework", dependencies: ["VibeCore"], path: "Sources/vibework"),
        .executableTarget(name: "vibeapp", dependencies: ["VibeCore"], path: "Sources/vibeapp")
    ]
)
