// swift-tools-version: 6.0
// MemoryKit — hot episodic spine (capture, recall, seal). Indexing/Knowledge/TCA → Anima package.

import PackageDescription

let package = Package(
    name: "MemoryKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "MemoryKit",
            targets: ["MemoryKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.18.0"),
    ],
    targets: [
        .target(
            name: "MemoryKit",
            dependencies: []
        ),
        .testTarget(
            name: "MemoryKitTests",
            dependencies: [
                "MemoryKit",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            exclude: [
                "__Snapshots__",
                "Snapshots/__Snapshots__",
            ]
        ),
    ]
)
