// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Andromeda",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "AndromedaBrand", targets: ["AndromedaBrand"]),
        .library(name: "AndromedaCore", targets: ["AndromedaCore"]),
        .library(name: "AndromedaAutoCache", targets: ["AndromedaAutoCache"]),
        .library(name: "AndromedaGateway", targets: ["AndromedaGateway"]),
        .library(name: "AndromedaHomeCore", targets: ["AndromedaHomeCore"]),
        .library(name: "AndromedaHUDCore", targets: ["AndromedaHUDCore"]),
        .library(name: "AndromedaDomain", targets: ["AndromedaDomain"]),
        .library(name: "AndromedaJournal", targets: ["AndromedaJournal"]),
        .library(name: "AndromedaMemory", targets: ["AndromedaMemory"]),
        .library(name: "AndromedaProjections", targets: ["AndromedaProjections"]),
        .library(name: "AndromedaSecrets", targets: ["AndromedaSecrets"]),
        .library(name: "AndromedaHostOps", targets: ["AndromedaHostOps"]),
        .library(name: "AndromedaTools", targets: ["AndromedaTools"]),
        .library(name: "AndromedaHTTP", targets: ["AndromedaHTTP"]),
        .library(name: "AndromedaClient", targets: ["AndromedaClient"]),
        .library(name: "AndromedaServer", targets: ["AndromedaServer"]),
        .executable(name: "andromeda", targets: ["AndromedaCLI"]),
        .executable(name: "andromeda-runtime", targets: ["AndromedaRuntimeCLI"]),
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
        .package(path: "Packages/Anima"),
        .package(path: "Packages/AndromedaUI"),
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite"
        ),
        .target(
            name: "AndromedaBrand",
            dependencies: [],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "AndromedaCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .target(
            name: "AndromedaDomain",
            dependencies: [],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "AndromedaJournal",
            dependencies: [
                "AndromedaDomain",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "AndromedaMemory",
            dependencies: [
                "CSQLite",
                "AndromedaDomain",
                "AndromedaJournal",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "AndromedaProjections",
            dependencies: [
                "AndromedaDomain",
                "AndromedaJournal",
                "AndromedaMemory",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "AndromedaSecrets",
            dependencies: [
                "AndromedaDomain",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "AndromedaHostOps",
            dependencies: [
                "AndromedaSecrets",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "AndromedaTools",
            dependencies: [
                "AndromedaDomain",
                "AndromedaSecrets",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "AndromedaHTTP",
            dependencies: [
                "AndromedaDomain",
                "AndromedaMemory",
                "AndromedaTools",
                .product(name: "Hummingbird", package: "hummingbird"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "AndromedaClient",
            dependencies: [
                "AndromedaDomain",
                "AndromedaMemory",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "AndromedaServer",
            dependencies: [
                "AndromedaDomain",
                "AndromedaJournal",
                "AndromedaMemory",
                "AndromedaProjections",
                "AndromedaSecrets",
                "AndromedaTools",
                "AndromedaHTTP",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
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
                "AndromedaBrand",
                "AndromedaCore",
                "AndromedaGateway",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .executableTarget(
            name: "AndromedaRuntimeCLI",
            dependencies: [
                "AndromedaBrand",
                "AndromedaHostOps",
                "AndromedaSecrets",
                "AndromedaServer",
                "AndromedaTools",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/andromeda-runtime",
            swiftSettings: [
                .swiftLanguageMode(.v6)
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
        .testTarget(
            name: "AndromedaDomainTests",
            dependencies: [
                "AndromedaDomain",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AndromedaJournalTests",
            dependencies: [
                "AndromedaDomain",
                "AndromedaJournal",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AndromedaToolsTests",
            dependencies: [
                "AndromedaSecrets",
                "AndromedaTools",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AndromedaHostOpsTests",
            dependencies: [
                "AndromedaHostOps",
                "AndromedaSecrets",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AndromedaHTTPTests",
            dependencies: [
                "AndromedaDomain",
                "AndromedaHTTP",
                "AndromedaMemory",
                "AndromedaSecrets",
                "AndromedaTools",
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AndromedaMemoryTests",
            dependencies: [
                "AndromedaDomain",
                "AndromedaJournal",
                "AndromedaMemory",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AndromedaProjectionTests",
            dependencies: [
                "AndromedaDomain",
                "AndromedaJournal",
                "AndromedaMemory",
                "AndromedaProjections",
            ],
            path: "Tests/AndromedaProjectionTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AndromedaSecretsTests",
            dependencies: [
                "AndromedaSecrets",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AndromedaBrandTests",
            dependencies: [
                "AndromedaBrand",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "RepositoryPolicyTests"
        ),
    ]
)
