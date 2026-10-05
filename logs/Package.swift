// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MajorTomLogs",
    platforms: [.macOS("26.0")],
    dependencies: [
        // For the log folder's location and the shared look.
        .package(path: "../transcriber/mac")
    ],
    targets: [
        .executableTarget(
            name: "MajorTomLogs",
            dependencies: [
                .product(name: "CallCore", package: "mac"),
                .product(name: "MajorTomStyle", package: "mac"),
            ],
            path: "Sources/MajorTomLogs",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
