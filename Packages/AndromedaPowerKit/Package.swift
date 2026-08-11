// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AndromedaPowerKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "AndromedaPowerKit",
            targets: ["AndromedaPowerKit"]
        )
    ],
    targets: [
        .target(
            name: "AndromedaPowerKit"
        ),
        .testTarget(
            name: "AndromedaPowerKitTests",
            dependencies: ["AndromedaPowerKit"]
        )
    ]
)
