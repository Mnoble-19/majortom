// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MajorTomCalls",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        // Exposed so the iOS app's Xcode project can depend on this package.
        .library(name: "CallCore", targets: ["CallCore"])
    ],
    targets: [
        .target(
            name: "CallCore",
            path: "Sources/CallCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "MajorTomCalls",
            dependencies: ["CallCore"],
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
