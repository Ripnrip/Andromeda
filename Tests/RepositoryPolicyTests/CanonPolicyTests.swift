import Foundation
import Testing

/// Swift canon policy — mechanical enforcement of the andromeda-swift-canon rules
/// that the PR #89 audit proved self-assessment cannot hold alone (HAB-1069).
///
/// Two scans, both seeded with the repository's pre-existing debt as an explicit
/// allowlist in the spirit of `RepositoryPolicyTests.allowlistedShellPaths`:
/// extending an allowlist entry requires explicit PR review approval — it is a
/// burn-down inventory, not a bypass.
///
/// - **Stringly wire fields.** `andromeda-swift-canon`: rich enums for external
///   `type` fields — a public `kind`/`status`/`type`/`action`/`severity`/`state`
///   property typed as bare `String` is a contract a typo can silently break.
/// - **Unknown-value tolerance.** A public `String` raw-value `Codable` enum with
///   a synthesized `init(from:)` **throws** on any value the producer adds first,
///   taking the whole decode down with it. Canon: explicit unknown-case handling
///   via a custom `init(from decoder:)`.
@Suite("Swift canon policy")
struct CanonPolicyTests {
    // MARK: - Policy tests

    @Test("stringly-typed public wire fields are forbidden beyond tracked debt")
    func rejectsStringlyTypedPublicWireFields() throws {
        let violations = try scannedSwiftFiles().flatMap { file -> [String] in
            let source = try String(contentsOf: file, encoding: .utf8)
            let names = Self.stringlyWireFieldNames(in: source)
            guard !names.isEmpty else { return [] }
            return names
                .map { "\(Self.repositoryRelative(file))#\($0)" }
                .filter { !Self.stringlyFieldDebt.contains($0) }
        }

        #expect(
            violations.isEmpty,
            """
            Public wire fields typed as bare String violate andromeda-swift-canon \
            (rich enums for external type fields). Type each as an enum with \
            unknown-value decoding, or — only with review approval — extend \
            `stringlyFieldDebt` in CanonPolicyTests:\
            \(violations.joined(separator: "\n"))
            """
        )
    }

    @Test("public String raw-value Codable enums must decode unknown values beyond tracked debt")
    func requiresUnknownValueDecodingOnPublicStringEnums() throws {
        let violations = try scannedSwiftFiles().flatMap { file -> [String] in
            let source = try String(contentsOf: file, encoding: .utf8)
            let names = Self.intolerantPublicStringEnumNames(in: source)
            guard !names.isEmpty else { return [] }
            return names
                .map { "\(Self.repositoryRelative(file))#\($0)" }
                .filter { !Self.intolerantEnumDebt.contains($0) }
        }

        #expect(
            violations.isEmpty,
            """
            Public String raw-value Codable enums without a custom `init(from:)` \
            throw on unknown values and kill the entire decode. Add explicit \
            unknown-case handling, or — only with review approval — extend \
            `intolerantEnumDebt` in CanonPolicyTests:\
            \(violations.joined(separator: "\n"))
            """
        )
    }

    // MARK: - Scanner unit tests (pure functions, no filesystem)

    @Test("stringly-field scanner matches shape, not prose")
    func stringlyFieldScannerIsPrecise() {
        let source = """
        public struct Wire: Codable {
            public let kind: String
            public var status: String
            public let summary: String
            let internalKind: String
            public let count: Int
        }
        /// docs mention `public let kind: String` without declaring one
        """
        #expect(Self.stringlyWireFieldNames(in: source) == ["kind", "status"])
    }

    @Test("enum scanner requires custom decoding, not just any initializer")
    func enumScannerRecognizesTolerance() {
        let intolerant = "public enum Kind: String, Codable {\n    case one\n}"
        let tolerant = """
        public enum Kind: String, Codable {
            case one
            public init(from decoder: Decoder) throws { self = .one }
        }
        """
        #expect(Self.intolerantPublicStringEnumNames(in: intolerant) == ["Kind"])
        #expect(Self.intolerantPublicStringEnumNames(in: tolerant).isEmpty)
    }

    // MARK: - Scanning

    /// Public `kind|status|type|action|severity|state` properties typed as bare `String`.
    /// Line comments are stripped first so prose *about* the pattern never counts as a declaration.
    private static func stringlyWireFieldNames(in source: String) -> [String] {
        let declarationLines = nonCommentLines(in: source)
        let regex = try! NSRegularExpression(
            pattern: #"(?m)public\s+(?:let|var)\s+(kind|status|type|action|severity|state)\s*:\s*String\b"#
        )
        let ns = declarationLines as NSString
        return regex.matches(in: declarationLines, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)) }
    }

    /// Public `String` raw-value `Codable` enums whose body lacks a custom `init(from`.
    private static func intolerantPublicStringEnumNames(in source: String) -> [String] {
        let declarationLines = nonCommentLines(in: source)
        let regex = try! NSRegularExpression(
            pattern: #"public\s+enum\s+(\w+)\s*:\s*([^{]*?\bString\b[^{]*?\bCodable\b[^{]*?)\{"#
        )
        let ns = declarationLines as NSString
        return regex.matches(in: declarationLines, range: NSRange(location: 0, length: ns.length))
            .filter { match in
                let bodyStart = match.range.location + match.range.length - 1
                let body = balancedBody(of: ns, startingAt: bodyStart)
                return body != nil && !body!.contains("init(from")
            }
            .map { ns.substring(with: $0.range(at: 1)) }
    }

    /// Drops `//`-prefixed lines so documentation prose is never scanned as declarations.
    private static func nonCommentLines(in source: String) -> String {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// Returns the brace-balanced body text starting at `openingBraceIndex`, or `nil` if unbalanced.
    private static func balancedBody(of ns: NSString, startingAt openingBraceIndex: Int) -> String? {
        var depth = 0
        var index = openingBraceIndex
        while index < ns.length {
            let character = ns.character(at: index)
            if character == 0x7B {
                depth += 1
            }
            if character == 0x7D {
                depth -= 1
                if depth == 0 {
                    return ns.substring(with: NSRange(location: openingBraceIndex, length: index - openingBraceIndex + 1))
                }
            }
            index += 1
        }
        return nil
    }

    // MARK: - Filesystem

    /// Swift sources under the project-maintained module roots, pruning generated and vendored directories.
    private func scannedSwiftFiles() throws -> [URL] {
        let root = repositoryRootURL()
        let excludedDirectoryNames: Set = [
            ".build", ".git", ".letta", ".swiftpm", "__Snapshots__", "DerivedData", "node_modules",
        ]
        var files: [URL] = []
        for moduleRootName in ["Sources", "Packages"] {
            let moduleRoot = root.appendingPathComponent(moduleRootName)
            guard let enumerator = FileManager.default.enumerator(
                at: moduleRoot,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                options: []
            ) else { continue }
            for case let fileURL as URL in enumerator {
                let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                if values.isDirectory == true, excludedDirectoryNames.contains(fileURL.lastPathComponent) {
                    enumerator.skipDescendants()
                } else if values.isRegularFile == true, fileURL.pathExtension == "swift" {
                    files.append(fileURL)
                }
            }
        }
        return files
    }

    /// Resolves the package root from this test source location without relying on the caller's working directory.
    private func repositoryRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func repositoryRelative(_ fileURL: URL) -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard let relative = fileURL.path.range(of: root.path + "/") else { return fileURL.path }
        return String(fileURL.path[relative.upperBound...])
    }

    // MARK: - Tracked debt (extending requires explicit PR review approval)

    /// Pre-existing stringly wire fields on main at HAB-1069 adoption — burn down, do not extend.
    private static let stringlyFieldDebt: Set<String> = [
        "Packages/Anima/Sources/AnimaIndexing/LadybugIndexer.swift#type",
        "Packages/MemoryKit/Sources/MemoryKit/ProjectState/OperatorProjectStateBridge.swift#state",
        "Packages/MemoryKit/Sources/MemoryKit/ProjectState/OperatorProjectStateBridge.swift#status",
        "Packages/MemoryKit/Sources/MemoryKit/Telemetry/HealthSnapshot.swift#status",
        "Sources/AndromedaAutoCache/Models.swift#type",
        "Sources/AndromedaDomain/EventEnvelope.swift#kind",
        "Sources/AndromedaDomain/Health.swift#status",
        "Sources/AndromedaHTTP/ControlPlaneRoute.swift#action",
        "Sources/AndromedaMCPHub/MemoryChainHealth.swift#kind",
        "Sources/AndromedaTools/ToolDefinition.swift#type",
    ]

    /// Pre-existing public String raw-value Codable enums without unknown-value decoding at HAB-1069 adoption.
    private static let intolerantEnumDebt: Set<String> = [
        "Packages/AndromedaGuardian/Sources/AndromedaGuardian/Guardian.swift#Method",
        "Packages/AndromedaGuardian/Sources/AndromedaGuardian/GuardianDomain.swift#MCPServerMarker",
        "Packages/AndromedaGuardian/Sources/AndromedaGuardian/GuardianDomain.swift#Rule",
        "Packages/AndromedaOrchestrator/Sources/AndromedaOrchestrator/OrchestratorModel.swift#Screen",
        "Packages/AndromedaOrchestrator/Sources/AndromedaOrchestrator/OrchestratorModel.swift#Wizard",
        "Packages/MemoryKit/Sources/MemoryKit/Curtain/JSONOutboxAuthority.swift#OutboxDeliveryState",
        "Packages/MemoryKit/Sources/MemoryKit/Curtain/MemoryComplexityCurtain.swift#CurtainHealthLevel",
        "Packages/MemoryKit/Sources/MemoryKit/Curtain/MemoryVerbSurface.swift#CurtainWriteKind",
        "Packages/MemoryKit/Sources/MemoryKit/Curtain/MemoryVerbSurface.swift#MemoryVerb",
        "Packages/MemoryKit/Sources/MemoryKit/Curtain/RetrievalPlanner.swift#RecallBackendRoute",
        "Packages/MemoryKit/Sources/MemoryKit/Curtain/RetrievalPlanner.swift#RecallQueryIntent",
        "Packages/MemoryKit/Sources/MemoryKit/ProjectState/ProjectStateModels.swift#ProjectStateStatus",
        "Packages/MemoryKit/Sources/MemoryKit/Registry/KnowledgeSyncPlan.swift#KnowledgeSyncDestinationStatus",
        "Packages/MemoryKit/Sources/MemoryKit/Registry/LaunchEntity.swift#HostRole",
        "Packages/MemoryKit/Sources/MemoryKit/Registry/LaunchEntity.swift#LaunchEntityAttention",
        "Packages/MemoryKit/Sources/MemoryKit/Registry/LaunchEntity.swift#LaunchEntityKind",
        "Packages/MemoryKit/Sources/MemoryKit/Registry/LaunchEntity.swift#LaunchEntityStatus",
        "Packages/MemoryKit/Sources/MemoryKit/Registry/MCPServerEntity.swift#MCPCapabilityID",
        "Packages/MemoryKit/Sources/MemoryKit/Registry/MCPServerEntity.swift#MCPServerSource",
        "Packages/MemoryKit/Sources/MemoryKit/Registry/SkillEntity.swift#SkillKind",
        "Packages/MemoryKit/Sources/MemoryKit/Registry/SkillEntity.swift#SkillSource",
        "Packages/MemoryKit/Sources/MemoryKit/Registry/SkillRegistry.swift#SkillScanFailureCode",
        "Packages/MemoryKit/Sources/MemoryKit/Security/VisibilityFilter.swift#VisibilityClass",
        "Packages/MemoryKit/Sources/MemoryKit/Services/LettaMemoryIngress.swift#MemoryVisibility",
        "Packages/MemoryKit/Sources/MemoryKit/Telemetry/HealthSnapshot.swift#FleetHealthStatus",
        "Packages/MemoryKit/Sources/MemoryKit/Telemetry/TelemetryClient.swift#TelemetryRecordKind",
        "Packages/MemoryKit/Sources/MemoryKit/Telemetry/TelemetryClient.swift#TelemetrySpanStatus",
        "Packages/MemoryKit/Sources/MemoryKit/UI/CommandCenterView.swift#CommandCenterActionIntent",
        "Packages/MemoryKit/Sources/MemoryKit/UI/FloatingPetView.swift#FloatingPetAmbientState",
        "Sources/AndromedaAutoCache/Models.swift#CacheStrategy",
        "Sources/AndromedaHTTP/ControlPlaneRoute.swift#ControlAction",
        "Sources/AndromedaHTTP/ControlPlaneRoute.swift#Status",
        "Sources/AndromedaHostOps/ChecklistModels.swift#Status",
        "Sources/AndromedaMCPHub/HubConfiguration.swift#HubPlacement",
        "Sources/AndromedaMCPHub/MemoryChainHealth.swift#Status",
        "Sources/AndromedaMemory/MemoryModels.swift#MemoryKind",
        "Sources/AndromedaMemory/MemoryModels.swift#MemoryRetryStatus",
        "Sources/AndromedaMemory/MemoryModels.swift#MemoryWriteStatus",
        "Sources/AndromedaMemory/MemoryModels.swift#PrivacyLevel",
        "Sources/AndromedaMemory/MemoryModels.swift#VerificationStatus",
    ]
}
