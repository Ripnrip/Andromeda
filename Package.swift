// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Andromeda",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "AndromedaCore", targets: ["AndromedaCore"]),
        .library(name: "AndromedaAutoCache", targets: ["AndromedaAutoCache"]),
        .library(name: "AndromedaGateway", targets: ["AndromedaGateway"]),
        .library(name: "AndromedaHomeCore", targets: ["AndromedaHomeCore"]),
        .library(name: "AndromedaHUDCore", targets: ["AndromedaHUDCore"]),
        .executable(name: "andromeda", targets: ["AndromedaCLI"]),
        .executable(name: "AndromedaHome", targets: ["AndromedaHome"]),
        .executable(name: "AndromedaHUD", targets: ["AndromedaHUD"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.25.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.80.0"),
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.3.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
        .package(path: "Packages/MemoryKit"),
    ],
    targets: [
        .target(
            name: "AndromedaCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .target(
            name: "AndromedaAutoCache",
            dependencies: [
                "AndromedaCore",
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .target(
            name: "AndromedaGateway",
            dependencies: [
                "AndromedaCore",
                "AndromedaAutoCache",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
            ]
        ),
        .executableTarget(
            name: "AndromedaCLI",
            dependencies: [
                "AndromedaCore",
                "AndromedaGateway",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .target(
            name: "AndromedaHomeCore",
            dependencies: [
                .product(name: "MemoryKit", package: "MemoryKit"),
            ],
            path: "Sources/AndromedaHomeCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "AndromedaHome",
            dependencies: [
                "AndromedaHomeCore",
            ],
            path: "Sources/AndromedaHome",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "AndromedaHUDCore",
            dependencies: [
                .product(name: "MemoryKit", package: "MemoryKit"),
            ],
            path: "Sources/AndromedaHUDCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "AndromedaHUD",
            dependencies: [
                "AndromedaHUDCore",
            ],
            path: "Sources/AndromedaHUD",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AndromedaHUDTests",
            dependencies: [
                "AndromedaHUDCore",
                .product(name: "MemoryKit", package: "MemoryKit"),
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            path: "Tests/AndromedaHUDTests",
            exclude: [
                "__Snapshots__",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AndromedaHomeTests",
            dependencies: [
                "AndromedaHomeCore",
                .product(name: "MemoryKit", package: "MemoryKit"),
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            path: "Tests/AndromedaHomeTests",
            exclude: [
                "__Snapshots__",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AndromedaAutoCacheTests",
            dependencies: [
                "AndromedaAutoCache",
                "AndromedaCore",
            ]
        ),
        .testTarget(
            name: "AndromedaGatewayTests",
            dependencies: [
                "AndromedaGateway",
                "AndromedaAutoCache",
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ]
        ),
    ]
)
