// swift-tools-version: 6.1
// Anima — memory subsystem package (Phase 1: Knowledge + Indexing + Core TCA)

import PackageDescription

let package = Package(
    name: "Anima",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "AnimaCore", targets: ["AnimaCore"]),
        .library(name: "AnimaKnowledge", targets: ["AnimaKnowledge"]),
        .library(name: "AnimaIndexing", targets: ["AnimaIndexing"]),
        .executable(name: "AnimaSample", targets: ["AnimaSample"]),
    ],
    dependencies: [
        .package(path: "../MemoryKit"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.15.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.18.0"),
    ],
    targets: [
        .target(name: "AnimaIndexing", dependencies: []),
        .target(
            name: "AnimaKnowledge",
            dependencies: [.product(name: "MemoryKit", package: "MemoryKit")]
        ),
        .target(
            name: "AnimaCore",
            dependencies: [
                .product(name: "MemoryKit", package: "MemoryKit"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ]
        ),
        .executableTarget(
            name: "AnimaSample",
            dependencies: [
                "AnimaCore",
                "AnimaKnowledge",
                "AnimaIndexing",
                .product(name: "MemoryKit", package: "MemoryKit"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
            path: "Sources/AnimaSample"
        ),
        .testTarget(
            name: "AnimaTests",
            dependencies: [
                "AnimaCore",
                "AnimaKnowledge",
                "AnimaIndexing",
                .product(name: "MemoryKit", package: "MemoryKit"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ]
        ),
    ]
)
