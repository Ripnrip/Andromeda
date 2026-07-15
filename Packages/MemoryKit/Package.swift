// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

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
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.15.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.18.0"),
    ],
    targets: [
        .target(
            name: "MemoryKit",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ]
        ),
        .testTarget(
            name: "MemoryKitTests",
            dependencies: [
                "MemoryKit",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ]
        ),
    ]
)
