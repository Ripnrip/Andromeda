// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AndromedaOrchestrator",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "AndromedaOrchestrator", targets: ["AndromedaOrchestrator"]),
    ],
    dependencies: [
        // Test-only: preview-parity snapshot baselines (same pin as AndromedaUI).
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
    ],
    targets: [
        .target(
            name: "AndromedaOrchestrator",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "AndromedaOrchestratorTests",
            dependencies: [
                "AndromedaOrchestrator",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
