// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MajorTom",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MajorTom",
            path: "Sources/MajorTom",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
