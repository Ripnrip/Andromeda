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
        .library(name: "AndromedaMCP", targets: ["AndromedaMCP"]),
        .library(name: "AndromedaGateway", targets: ["AndromedaGateway"]),
        .executable(name: "andromeda", targets: ["AndromedaCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.25.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.80.0"),
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.3.0"),
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
            name: "AndromedaMCP",
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
                "AndromedaMCP",
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
                "AndromedaMCP",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
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
            name: "AndromedaMCPTests",
            dependencies: [
                "AndromedaMCP",
                "AndromedaCore",
            ]
        ),
        .testTarget(
            name: "AndromedaGatewayTests",
            dependencies: [
                "AndromedaGateway",
                "AndromedaAutoCache",
                "AndromedaMCP",
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ]
        ),
    ]
)
