import Foundation
@testable import MemoryKit
import Testing

/// 🎭 Fake runner that drives git for real but through the ProcessRunning seam.
/// We use the real git binary against a temp repo so behavior matches production,
/// while the *seam* (injection point) stays identical to the mocked test path.
private actor RecordingRunner: ProcessRunning {
    struct Invocation: Sendable, Equatable {
        let executable: String
        let arguments: [String]
    }

    private(set) var invocations: [Invocation] = []
    private let real = LocalProcessRunner(timeoutSeconds: 15)

    func run(executable: String, arguments: [String], workingDirectory: URL?) async throws -> ProcessRunResult {
        invocations.append(Invocation(executable: executable, arguments: arguments))
        return try await real.run(executable: executable, arguments: arguments, workingDirectory: workingDirectory)
    }
}

private func makeTempMemFS(agentID: String = "0000aabb-1234-cccc") throws -> (root: URL, memory: URL) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("letta-ingress-test-\(UUID().uuidString)", isDirectory: true)
    let memory = root
        .appendingPathComponent("agent-\(agentID)", isDirectory: true)
        .appendingPathComponent("memory", isDirectory: true)
    try FileManager.default.createDirectory(at: memory, withIntermediateDirectories: true)
    let init2 = Process()
    init2.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    init2.arguments = ["init", "-q"]
    init2.currentDirectoryURL = memory
    try init2.run(); init2.waitUntilExit()
    return (root, memory)
}

private let sampleFact = LettaMemoryFact(
    title: "Process Identity Canon",
    body: "TCC dialogs name the requesting binary's code identity.",
    visibility: .internal,
    tags: ["canon", "tcc"],
    source: "test-suite"
)

@Test("write lands file under system/knowledge and returns sealed receipt")
func writeLandsInCoreMemory() async throws {
    let (root, memory) = try makeTempMemFS()
    let writer = GitBackedLettaWriter(memfsRoot: root)

    let receipt = try await writer.write(sampleFact, to: "0000aabb-1234-cccc")

    #expect(receipt.relativePath == "system/knowledge/process-identity-canon.md")
    #expect(receipt.unchanged == false)
    #expect(receipt.contentHash.hasPrefix("sha256:"))
    #expect(receipt.commitSHA.count == 40)

    let onDisk = try String(contentsOf: memory.appendingPathComponent(receipt.relativePath), encoding: .utf8)
    #expect(onDisk.contains("visibility: internal"))
    #expect(onDisk.contains("source: test-suite"))
    #expect(onDisk.contains("TCC dialogs name"))
    // Contract: frontmatter may contain ONLY `description` (memfs pre-commit hook, 2026-09-05).
    let lines = onDisk.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    #expect(lines.first == "---")
    let closing = lines.dropFirst().firstIndex(of: "---")
    #expect(closing != nil)
    if let closing {
        let fmLines = Array(lines[1 ..< closing])
        #expect(fmLines.contains { $0.hasPrefix("description:") })
        #expect(!fmLines.contains { $0.hasPrefix("title:") })
        #expect(!fmLines.contains { $0.hasPrefix("visibility:") })
    }
}

@Test("idempotency: same fact twice produces one commit and an unchanged receipt")
func idempotentRewrite() async throws {
    let (root, _) = try makeTempMemFS()
    let writer = GitBackedLettaWriter(memfsRoot: root)

    let first = try await writer.write(sampleFact, to: "0000aabb-1234-cccc")
    let second = try await writer.write(sampleFact, to: "0000aabb-1234-cccc")

    #expect(second.unchanged == true)
    #expect(second.commitSHA == first.commitSHA)
    #expect(second.contentHash == first.contentHash)
}

@Test("visibility tag is mandatory in the rendered file")
func visibilityIsRendered() async throws {
    let (root, memory) = try makeTempMemFS()
    let writer = GitBackedLettaWriter(memfsRoot: root)

    let receipt = try await writer.write(
        LettaMemoryFact(title: "Cloak Check", body: "x", visibility: .public, source: "test-suite"),
        to: "0000aabb-1234-cccc"
    )
    let onDisk = try String(contentsOf: memory.appendingPathComponent(receipt.relativePath), encoding: .utf8)
    #expect(onDisk.contains("visibility: public"))
}

@Test("empty title is rejected")
func emptyTitleRejected() async throws {
    let (root, _) = try makeTempMemFS()
    let writer = GitBackedLettaWriter(memfsRoot: root)
    await #expect(throws: LettaIngressError.emptyTitle) {
        _ = try await writer.write(
            LettaMemoryFact(title: "   ", body: "x", visibility: .private, source: "test-suite"),
            to: "0000aabb-1234-cccc"
        )
    }
}

@Test("missing memfs is reported with its path")
func missingMemFS() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("letta-ingress-missing-\(UUID().uuidString)", isDirectory: true)
    let writer = GitBackedLettaWriter(memfsRoot: root)
    await #expect(throws: LettaIngressError.self) {
        _ = try await writer.write(sampleFact, to: "ghost-agent")
    }
}

@Test("slug derivation is kebab-case and safe")
func slugDerivation() {
    #expect(LettaMemoryFact(title: "Hello, World!", body: "b", visibility: .internal, source: "t").slug == "hello-world")
    #expect(LettaMemoryFact(title: "TCC & Canon — v2", body: "b", visibility: .internal, source: "t").slug == "tcc-canon-v2")
}

@Test("HIGH regression: newline-bearing title cannot inject frontmatter keys")
func frontmatterInjectionRejected() async throws {
    let (root, _) = try makeTempMemFS()
    let writer = GitBackedLettaWriter(memfsRoot: root)
    // A title that would smuggle `read_only` / extra keys into the YAML block.
    let hostile = LettaMemoryFact(
        title: "x\nread_only: true\nlimit: 0",
        body: "b",
        visibility: .private,
        source: "test-suite"
    )
    await #expect(throws: LettaIngressError.titleUnsafeForFrontmatter) {
        _ = try await writer.write(hostile, to: "0000aabb-1234-cccc")
    }
    // Colons-after-space and leading metacharacters are also rejected.
    for hostileTitle in ["- reads like a flag", "key: value title", "# comment-ish"] {
        await #expect(throws: LettaIngressError.titleUnsafeForFrontmatter) {
            _ = try await writer.write(
                LettaMemoryFact(title: hostileTitle, body: "b", visibility: .private, source: "test-suite"),
                to: "0000aabb-1234-cccc"
            )
        }
    }
}

@Test("MEDIUM regression: traversal-bearing agentIDs are rejected")
func agentIDAllowlist() async throws {
    let (root, _) = try makeTempMemFS()
    let writer = GitBackedLettaWriter(memfsRoot: root)
    for badID in ["../../etc", "foo/../bar", "/absolute", "a b", "id;rm", ""] {
        await #expect(throws: LettaIngressError.self) {
            _ = try await writer.write(sampleFact, to: badID)
        }
    }
    // Valid backend-style ID passes the gate (fails as memfsMissing, NOT allowlist).
    do {
        _ = try await writer.write(sampleFact, to: "4fd6a77b-6439-4f2a-8605-01e131d15536")
        Issue.record("expected memfsMissing for nonexistent valid ID")
    } catch let e as LettaIngressError {
        guard case .memfsMissing = e else {
            Issue.record("expected memfsMissing, got \(e)")
            return
        }
    }
}

/// 🎭 Runner that fakes the letta CLI token census for the verification leg.
private actor FakeCLIRunner: ProcessRunning {
    let tokenJSON: String
    init(tokenJSON: String) {
        self.tokenJSON = tokenJSON
    }

    private let real = LocalProcessRunner(timeoutSeconds: 15)

    func run(executable: String, arguments: [String], workingDirectory: URL?) async throws -> ProcessRunResult {
        if arguments.contains("tokens") {
            return ProcessRunResult(exitCode: 0, stdout: tokenJSON, stderr: "")
        }
        return try await real.run(executable: executable, arguments: arguments, workingDirectory: workingDirectory)
    }
}

@Test("cliTokens verification passes when the census lists our file")
func cliVerificationPass() async throws {
    let (root, _) = try makeTempMemFS()
    let json = #"{"total_tokens": 176, "files": [{"path": "system/knowledge/process-identity-canon.md", "tokens": 176}]}"#
    let writer = GitBackedLettaWriter(
        memfsRoot: root,
        runner: FakeCLIRunner(tokenJSON: json),
        verification: .cliTokens(lettaJS: URL(fileURLWithPath: "/fake/letta.js"), node: "/fake/node")
    )
    let receipt = try await writer.write(sampleFact, to: "0000aabb-1234-cccc")
    #expect(receipt.relativePath == "system/knowledge/process-identity-canon.md")
}

@Test("cliTokens verification fails when the census omits our file")
func cliVerificationFail() async throws {
    let (root, _) = try makeTempMemFS()
    let json = #"{"total_tokens": 0, "files": []}"#
    let writer = GitBackedLettaWriter(
        memfsRoot: root,
        runner: FakeCLIRunner(tokenJSON: json),
        verification: .cliTokens(lettaJS: URL(fileURLWithPath: "/fake/letta.js"), node: "/fake/node")
    )
    await #expect(throws: LettaIngressError.self) {
        _ = try await writer.write(sampleFact, to: "0000aabb-1234-cccc")
    }
}

/// 🌐 Live E2E against the real Studio-Agent memfs. Only runs when
/// LETTA_LIVE_E2E=1 is set — never in CI. Writes a dated proof entry to the
/// agent's real core memory and verifies via git lifecycle.
@Test(.enabled(if: ProcessInfo.processInfo.environment["LETTA_LIVE_E2E"] == "1"))
func liveE2EAgainstStudioAgent() async throws {
    let writer = GitBackedLettaWriter()
    let fact = LettaMemoryFact(
        title: "Phase 1 live E2E",
        body: "GitBackedLettaWriter drove a real write into this agent's core memory on 2026-09-05. The Anima ingress lane is proven end-to-end.",
        visibility: .internal,
        tags: ["proof", "anima"],
        source: "memorykit-test-suite"
    )
    let receipt = try await writer.write(fact, to: "local-4fd6a77b-6439-4f2a-8605-01e131d15536")
    #expect(receipt.relativePath == "system/knowledge/phase-1-live-e2e.md")
}
