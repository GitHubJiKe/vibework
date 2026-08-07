// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "vibework",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "vibework", path: "Sources/vibework")
    ]
)
