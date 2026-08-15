# SPM — Package Practices

## Structure

```
Package/
├── Package.swift
├── Sources/MyLib/
└── Tests/MyLibTests/
```

## Package.swift

```swift
// swift-tools-version: 6.0
let package = Package(
    name: "MyLib",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "MyLib", targets: ["MyLib"])],
    dependencies: [ … ],
    targets: [
        .target(name: "MyLib", dependencies: [ … ]),
        .testTarget(name: "MyLibTests", dependencies: ["MyLib"]),
    ]
)
```

## Rules

- One library product per domain
- Acyclic dependencies
- `path:` deps for monorepo local packages
- `PreviewSupport` / test fixtures — not in Release app target
- UI packages don't import server packages

## Strict concurrency

```swift
.target(name: "MyLib", swiftSettings: [.enableUpcomingFeature("StrictConcurrency")])
```

## CI

```bash
swift build --package-path Packages/MyLib
swift test --package-path Packages/MyLib
```

Build dependency order: core → client → UI.

## Domain package graph

Anima/ANDROMEDIA layout → **anima-swift** `spm-modularity.md`.
