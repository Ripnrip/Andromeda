// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "AndromedaGuardian",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "AndromedaGuardian", targets: ["AndromedaGuardian"]),
    ],
    targets: [
        .target(
            name: "AndromedaGuardian",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "AndromedaGuardianTests",
            dependencies: ["AndromedaGuardian"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
