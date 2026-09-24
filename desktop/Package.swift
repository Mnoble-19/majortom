// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MajorTom",
    platforms: [.macOS("26.0")],
    dependencies: [
        // Shared with the calls transcriber. The wire format the phone syncs
        // over lives there; duplicating it here would let the two drift.
        .package(path: "../transcriber/mac")
    ],
    targets: [
        .executableTarget(
            name: "MajorTom",
            dependencies: [
                .product(name: "CallCore", package: "mac"),
                .product(name: "MajorTomStyle", package: "mac"),
            ],
            path: "Sources/MajorTom",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
