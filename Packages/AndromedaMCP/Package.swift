// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "AndromedaMCP",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "andromeda-mcp", targets: ["andromeda-mcp"]),
    ],
    targets: [
        .executableTarget(
            name: "andromeda-mcp",
            path: "Sources/AndromedaMCP",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AndromedaMCPTests",
            dependencies: ["andromeda-mcp"],
            path: "Tests/AndromedaMCPTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)
