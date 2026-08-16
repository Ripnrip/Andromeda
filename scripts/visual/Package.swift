// swift-tools-version:6.0
import PackageDescription

// Orchestrator for the web visual-diff pipeline. The repository forbids
// project-maintained shell automation (AGENTS.md / RepositoryPolicyTests),
// so build/serve/capture/publish/comment orchestration lives here, typed.
// The Node capture scripts (shot.mjs / diff.mjs) stay Node: Playwright and
// pixelmatch are JS-native, and the runner invokes them as subprocesses.
let package = Package(
    name: "visual-diff",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "VisualDiffCore",
            path: "Sources/VisualDiffCore"
        ),
        .executableTarget(
            name: "visual-diff",
            dependencies: ["VisualDiffCore"],
            path: "Sources/VisualDiff"
        ),
        .testTarget(
            name: "VisualDiffTests",
            dependencies: ["VisualDiffCore"],
            path: "Tests/VisualDiffTests"
        ),
    ]
)
