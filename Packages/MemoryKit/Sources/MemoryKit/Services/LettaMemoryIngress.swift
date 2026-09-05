import CryptoKit
import Foundation

/// 🛡️ Visibility/cloak tag — mandatory on every ingress write (multibrain AGENTS.md rule).
public enum MemoryVisibility: String, Sendable, Codable, CaseIterable {
    case `public`, friends, `private`, `internal`
}

/// 📝 A fact to be delivered into a local Letta agent's core memory.
public struct LettaMemoryFact: Sendable, Equatable {
    /// Human title (becomes the slug and H1).
    public let title: String
    /// Markdown body.
    public let body: String
    /// Visibility/cloak tag. No default — a write without a tag is a rejected write.
    public let visibility: MemoryVisibility
    /// Optional classification tags.
    public let tags: [String]
    /// Attributing source (e.g. "andromeda-hub", "hermes-agent").
    public let source: String

    public init(title: String, body: String, visibility: MemoryVisibility, tags: [String] = [], source: String) {
        self.title = title
        self.body = body
        self.visibility = visibility
        self.tags = tags
        self.source = source
    }

    /// kebab-case slug derived from the title; empty titles are rejected by the writer.
    public var slug: String {
        let lowered = title.lowercased()
        var out = ""
        var lastWasDash = false
        for scalar in lowered.unicodeScalars {
            let isAlnum = (scalar.value >= 48 && scalar.value <= 57) || (scalar.value >= 97 && scalar.value <= 122)
            if isAlnum {
                out.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash, !out.isEmpty {
                out.append("-")
                lastWasDash = true
            }
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

/// 🧾 Proof of delivery: where the fact landed and under which commit.
public struct LettaMemoryReceipt: Sendable, Equatable {
    public let agentID: String
    /// Path relative to the agent's memory root (always under `system/knowledge/`).
    public let relativePath: String
    /// Git commit SHA sealing the write.
    public let commitSHA: String
    /// `sha256:<hex>` of the rendered file — the idempotency join key.
    public let contentHash: String
    /// True when an identical fact was already present (no new commit).
    public let unchanged: Bool

    public init(agentID: String, relativePath: String, commitSHA: String, contentHash: String, unchanged: Bool) {
        self.agentID = agentID
        self.relativePath = relativePath
        self.commitSHA = commitSHA
        self.contentHash = contentHash
        self.unchanged = unchanged
    }
}

/// 🌩️ Ingress failures.
public enum LettaIngressError: Error, LocalizedError, Sendable, Equatable {
    case memfsMissing(path: String)
    case emptyTitle
    case emptyBody
    case slugInvalid(String)
    case gitFailed(step: String, stderr: String)
    case verificationFailed(reason: String)
    /// Title cannot be safely rendered as a single-line YAML scalar.
    case titleUnsafeForFrontmatter
    /// agentID failed the memfs charset allowlist.
    case agentIDInvalid(String)

    public var errorDescription: String? {
        switch self {
        case let .memfsMissing(path):
            "🌩️ Agent memfs not found at \(path) — is the agent registered with the local backend?"
        case .emptyTitle:
            "🌩️ Ingress fact has no title — the slug cannot be conjured from silence."
        case .emptyBody:
            "🌩️ Ingress fact has no body — the quill refuses blank parchment."
        case let .slugInvalid(slug):
            "🌩️ Title '\(slug)' produced an unusable slug."
        case let .gitFailed(step, stderr):
            "🌩️ git \(step) failed: \(stderr)"
        case let .verificationFailed(reason):
            "🌩️ Post-write verification failed: \(reason)"
        case .titleUnsafeForFrontmatter:
            "🌩️ Title contains characters unsafe for single-line YAML frontmatter (newlines, control chars, or leading metacharacters)."
        case let .agentIDInvalid(id):
            "🌩️ agentID '\(id)' failed the memfs charset allowlist (expected hex + hyphen)."
        }
    }
}

/// ✍️ The curtain-facing contract: deliver a fact into a local Letta agent's memory.
public protocol LettaMemoryWriting: Sendable {
    /// Write (or idempotently confirm) `fact` in the agent's core memory.
    func write(_ fact: LettaMemoryFact, to agentID: String) async throws -> LettaMemoryReceipt
}

/// 🔍 How strictly a write is verified after the commit seals.
public enum IngressVerification: Sendable, Equatable {
    /// Git lifecycle only (add → commit → clean tree).
    case gitOnly
    /// Additionally ask the bundled Letta CLI (`letta memory tokens`) to confirm the
    /// file is counted in-context core memory. `lettaJS` = bundled letta.js path;
    /// `node` = node executable.
    case cliTokens(lettaJS: URL, node: String)
}

/// 📊 Decoded shape of `letta memory tokens --format json` (the in-context census).
struct MemoryTokenReport: Decodable, Sendable {
    struct FileEntry: Decodable, Sendable {
        let path: String
        let tokens: Int
    }

    let total_tokens: Int
    let files: [FileEntry]
}

/// 🌟 GitBackedLettaWriter — the local-first ingress implementation.
///
/// Writes `system/knowledge/<slug>.md` into the agent's git-backed memfs and
/// commits it under the attributable identity `andromeda-memory-ingress`.
/// Verification is observable: `git status --porcelain` must be clean after commit.
///
/// All shell work flows through the injected `ProcessRunning` (see
/// RetrievalService.swift) — never a baked `Foundation.Process` in tests.
public actor GitBackedLettaWriter: LettaMemoryWriting {
    /// 🔑 The git identity under which every ingress write is sealed.
    public static let authorName = "andromeda-memory-ingress"
    public static let authorEmail = "ingress@andromeda.local"

    /// 🗄️ Root containing per-agent memfs dirs (`agent-<id>/memory`).
    private let memfsRoot: URL
    private let runner: any ProcessRunning
    private let verification: IngressVerification

    public init(
        memfsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".letta/lc-local-backend/memfs", isDirectory: true),
        runner: any ProcessRunning = LocalProcessRunner(timeoutSeconds: 15),
        verification: IngressVerification = .gitOnly
    ) {
        self.memfsRoot = memfsRoot
        self.runner = runner
        self.verification = verification
    }

    public func write(_ fact: LettaMemoryFact, to agentID: String) async throws -> LettaMemoryReceipt {
        guard !fact.title.trimmingCharacters(in: .whitespaces).isEmpty else { throw LettaIngressError.emptyTitle }
        guard !fact.body.trimmingCharacters(in: .whitespaces).isEmpty else { throw LettaIngressError.emptyBody }
        let slug = fact.slug
        guard !slug.isEmpty, !slug.contains(".."), !slug.contains("/") else { throw LettaIngressError.slugInvalid(slug) }
        // HARD GATE: frontmatter is attacker-controlled input interpolated into YAML.
        // A title containing newlines/colons could inject extra frontmatter keys
        // (e.g. read_only) into files Letta loads as in-context core memory.
        // The rendered description must stay a single scalar line.
        let safeTitle = Self.yamlSafe(fact.title)
        guard safeTitle != nil else { throw LettaIngressError.titleUnsafeForFrontmatter }
        _ = safeTitle // render() re-validates; kept here to fail fast on the write path
        // Path containment: agentID selects a memfs dir; restrict to the exact charset
        // the local backend generates (hex + hyphen) so no `..`/`/`/absolute escape
        // can survive appendingPathComponent.
        guard Self.isValidAgentID(agentID) else { throw LettaIngressError.agentIDInvalid(agentID) }

        let memoryRoot = memfsRoot
            .appendingPathComponent("agent-\(agentID)", isDirectory: true)
            .appendingPathComponent("memory", isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: memoryRoot.path, isDirectory: &isDir), isDir.boolValue else {
            throw LettaIngressError.memfsMissing(path: memoryRoot.path)
        }

        let relativePath = "system/knowledge/\(slug).md"
        let rendered = try Self.render(fact: fact, slug: slug)
        let hash = Self.contentHash(of: rendered)

        let target = memoryRoot.appendingPathComponent(relativePath)
        if let existing = try? String(contentsOf: target, encoding: .utf8),
           Self.contentHash(of: existing) == hash
        {
            // Idempotency: identical fact already sealed — report, don't duplicate.
            let sha = try await gitRevParseHead(at: memoryRoot)
            return LettaMemoryReceipt(agentID: agentID, relativePath: relativePath, commitSHA: sha, contentHash: hash, unchanged: true)
        }

        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try rendered.write(to: target, atomically: true, encoding: .utf8)

        _ = try await git(at: memoryRoot, ["add", relativePath])
        _ = try await git(at: memoryRoot, [
            "-c", "user.name=\(Self.authorName)",
            "-c", "user.email=\(Self.authorEmail)",
            "commit", "-m", "memory.write: \(fact.title) (visibility: \(fact.visibility.rawValue))",
        ])
        let sha = try await gitRevParseHead(at: memoryRoot)

        // Observability gate: tree must be clean after our commit.
        let status = try await git(at: memoryRoot, ["status", "--porcelain"])
        guard status.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LettaIngressError.gitFailed(step: "verify-clean", stderr: status.stdout)
        }

        // Optional in-context verification: the bundled CLI's token census must list
        // our file (only `system/**` is injected into the agent's core memory).
        if case let .cliTokens(lettaJS, node) = verification {
            let report = try await lettaTokens(agentID: agentID, lettaJS: lettaJS, node: node)
            guard report.files.contains(where: { $0.path == relativePath }) else {
                throw LettaIngressError.verificationFailed(
                    reason: "letta memory tokens does not count \(relativePath) in-context (total=\(report.total_tokens), files=\(report.files.map(\.path)))"
                )
            }
        }

        return LettaMemoryReceipt(agentID: agentID, relativePath: relativePath, commitSHA: sha, contentHash: hash, unchanged: false)
    }

    // MARK: - Rendering & hashing

    /// Render the fact as the markdown file the agent's system prompt will load.
    ///
    /// Contract (from the memfs pre-commit hook, read live 2026-09-05): staged
    /// `.md` files under `system/` or `reference/` may carry ONLY the
    /// frontmatter keys `description` (required, non-empty), `read_only`
    /// (protected), `limit` (legacy). All other metadata rides in the body.
    static func render(fact: LettaMemoryFact, slug: String) throws -> String {
        // yamlSafe is re-validated here so direct calls of `render` cannot bypass
        // the write-path hard gate (defense in depth; write() checks first).
        guard let safeTitle = yamlSafe(fact.title) else { throw LettaIngressError.titleUnsafeForFrontmatter }
        let date = Date().formatted(.iso8601.year().month().day())
        let tagLine = fact.tags.isEmpty ? "" : "\n- tags: \(fact.tags.joined(separator: ", "))"
        return """
        ---
        description: \(safeTitle)
        ---

        # \(fact.title)

        - visibility: \(fact.visibility.rawValue)
        - source: \(fact.source)\(tagLine)
        - date: \(date)
        - slug: \(slug)

        \(fact.body)
        """
    }

    static func contentHash(of text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Input hardening (Cursor security review 2026-09-05: HIGH + MEDIUM)

    /// True when the string is safe as a bare single-line YAML scalar:
    /// no newlines, no control characters, no leading YAML metacharacters,
    /// and no `: ` / ` #` sequences that could read as a key or comment.
    static func yamlSafe(_ s: String) -> String? {
        guard !s.contains(where: { $0.isNewline || $0 == "\0" || ($0.asciiValue.map { $0 < 0x20 } ?? false) })
        else { return nil }
        let first = s.first
        guard first != nil else { return nil }
        guard !"-?:&#*@`\"'%|>[]{}!".contains(first!) else { return nil }
        guard !s.contains(": "), !s.contains(" #") else { return nil }
        // Collapse any residual whitespace runs (defensive; newline already rejected).
        return s
    }

    /// agentID allowlist: hex + hyphen only (the local backend mints UUID-ish IDs).
    /// Rejects empty, `..`, separators, and anything path-bearing.
    static func isValidAgentID(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 128 else { return false }
        return id.allSatisfy { c in
            c.isHexDigit || c == "-"
        }
    }

    // MARK: - git plumbing (all via injected ProcessRunning)

    private func git(at cwd: URL, _ args: [String]) async throws -> ProcessRunResult {
        let result = try await runner.run(executable: "/usr/bin/git", arguments: args, workingDirectory: cwd)
        guard result.exitCode == 0 else {
            throw LettaIngressError.gitFailed(step: args.prefix(2).joined(separator: " "), stderr: result.stderr)
        }
        return result
    }

    private func gitRevParseHead(at cwd: URL) async throws -> String {
        let result = try await git(at: cwd, ["rev-parse", "HEAD"])
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 🔍 Ask the bundled Letta CLI for the in-context token census of an agent.
    private func lettaTokens(agentID: String, lettaJS: URL, node: String) async throws -> MemoryTokenReport {
        let result = try await runner.run(
            executable: node,
            arguments: [lettaJS.path, "memory", "tokens", "--agent", agentID, "--format", "json"],
            workingDirectory: nil
        )
        guard result.exitCode == 0 else {
            throw LettaIngressError.verificationFailed(reason: "letta memory tokens exited \(result.exitCode): \(result.stderr)")
        }
        guard let data = result.stdout.data(using: .utf8),
              let report = try? JSONDecoder().decode(MemoryTokenReport.self, from: data)
        else {
            throw LettaIngressError.verificationFailed(reason: "unparseable tokens JSON: \(result.stdout.prefix(200))")
        }
        return report
    }
}
