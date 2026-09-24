// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MajorTomCalls",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        // Exposed so the iOS app's Xcode project can depend on this package.
        .library(name: "CallCore", targets: ["CallCore"]),
        // The palette and small layout pieces every MajorTom app shares.
        .library(name: "MajorTomStyle", targets: ["MajorTomStyle"])
    ],
    targets: [
        .target(
            name: "CallCore",
            path: "Sources/CallCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "MajorTomStyle",
            path: "Sources/MajorTomStyle",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "MajorTomCalls",
            dependencies: ["CallCore", "MajorTomStyle"],
            path: "Sources/MajorTomCalls",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Probe",
            dependencies: ["CallCore"],
            path: "Sources/Probe",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
