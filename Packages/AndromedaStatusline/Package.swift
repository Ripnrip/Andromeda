// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "AndromedaStatusline",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "andromeda-statusline", targets: ["andromeda-statusline"]),
    ],
    targets: [
        .executableTarget(
            name: "andromeda-statusline",
            path: "Sources/AndromedaStatusline",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "AndromedaStatuslineTests",
            dependencies: ["andromeda-statusline"],
            path: "Tests/AndromedaStatuslineTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
