/**
 * 🎭 The RetrievalService - The Librarian of the Hot Archive
 *
 * "First we whisper to the local ledger — tags, projects, dates, cloaks —
 * and only if the shelves feel thin do we send ripgrep into the vault fog.
 * Vectors may glitter later; success never waits on their lights."
 *
 * - The Enchanted Recall Observatory of Anima
 */

import Foundation

// MARK: - Query & Hits

/// 🌟 RecallQuery — the seeker's lantern for `recall_memory`.
public struct RecallQuery: Sendable, Equatable {
    /// Free-text needle matched against narrative (hot) and vault files (ripgrep).
    public var text: String?
    /// Require all listed tags to be present on hot-store records.
    public var tags: [String]?
    /// Exact project match when set.
    public var project: String?
    /// Exact visibility class when set (`public` | `friends` | `private` | `internal`).
    public var visibility: String?
    /// Inclusive lower bound on `createdAt`.
    public var dateFrom: Date?
    /// Inclusive upper bound on `createdAt`.
    public var dateTo: Date?
    /// Maximum hits to return after merge/rank.
    public var limit: Int
    /// When true, attempt vault ripgrep if hot results are below `limit`.
    public var includeVaultFallback: Bool

    // 🌟 The Seeker's Brief - Assemble the lantern with sensible defaults
    public init(
        text: String? = nil,
        tags: [String]? = nil,
        project: String? = nil,
        visibility: String? = nil,
        dateFrom: Date? = nil,
        dateTo: Date? = nil,
        limit: Int = 20,
        includeVaultFallback: Bool = true
    ) {
        self.text = text
        self.tags = tags
        self.project = project
        self.visibility = visibility
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.limit = max(1, limit)
        self.includeVaultFallback = includeVaultFallback
    }
}

/// 🌟 MemoryHit — a ranked recollection from hot store and/or vault.
public struct MemoryHit: Sendable, Identifiable, Equatable {
    public enum Source: String, Sendable, Equatable {
        case hotStore
        case vault
    }

    public let id: UUID
    public let memoryID: UUID?
    public let contentHash: String?
    public let narrative: String
    public let project: String?
    public let visibility: String?
    public let tags: [String]
    public let createdAt: Date?
    public let path: String?
    public let source: Source
    /// Higher is better; used for merge ranking (recency + tag/text boosts).
    public let score: Double

    // 🌟 Crystallize a hit for the seeker's tray
    public init(
        id: UUID = UUID(),
        memoryID: UUID? = nil,
        contentHash: String? = nil,
        narrative: String,
        project: String? = nil,
        visibility: String? = nil,
        tags: [String] = [],
        createdAt: Date? = nil,
        path: String? = nil,
        source: Source,
        score: Double
    ) {
        self.id = id
        self.memoryID = memoryID
        self.contentHash = contentHash
        self.narrative = narrative
        self.project = project
        self.visibility = visibility
        self.tags = tags
        self.createdAt = createdAt
        self.path = path
        self.source = source
        self.score = score
    }
}

/// 🌟 Aggregate outcome of a recall — always succeeds without Qdrant/Ladybug.
public struct RecallResult: Sendable, Equatable {
    public let hits: [MemoryHit]
    public let hotHitCount: Int
    public let vaultHitCount: Int
    /// True when vault ripgrep was skipped (missing path) or failed open.
    public let vaultDegraded: Bool
    public let degradationReason: String?

    public init(
        hits: [MemoryHit],
        hotHitCount: Int,
        vaultHitCount: Int,
        vaultDegraded: Bool,
        degradationReason: String? = nil
    ) {
        self.hits = hits
        self.hotHitCount = hotHitCount
        self.vaultHitCount = vaultHitCount
        self.vaultDegraded = vaultDegraded
        self.degradationReason = degradationReason
    }
}

// MARK: - Injectable Process Runner

/// 🌟 ProcessRunResult — stdout/stderr envelope from a spawned ritual.
public struct ProcessRunResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// 🌟 ProcessRunning — mockable shell for vault ripgrep (never bake Foundation.Process into tests).
public protocol ProcessRunning: Sendable {
    func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL?
    ) async throws -> ProcessRunResult
}

/// 💥 Hard failures from the local process runner (timeout / spawn).
public enum LocalProcessRunnerError: Error, LocalizedError, Sendable, Equatable {
    case timedOut(seconds: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .timedOut(let seconds):
            return "Process timed out after \(String(format: "%.1f", seconds))s"
        }
    }
}

/// 🌟 LocalProcessRunner — real `Process` invocation for production ripgrep.
///
/// Drains stdout/stderr **concurrently** while waiting — never `waitUntilExit` before
/// reading (that deadlocks when rg emits more than the pipe buffer, e.g. query `"test"`).
public struct LocalProcessRunner: ProcessRunning {
    /// Kill + fail if the child exceeds this wall time (HUD / recall must stay snappy).
    public var timeoutSeconds: TimeInterval

    public init(timeoutSeconds: TimeInterval = 2.0) {
        self.timeoutSeconds = timeoutSeconds
    }

    // 🌐 Spawn a local executable and capture its chorus of stdout/stderr
    public func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL?
    ) async throws -> ProcessRunResult {
        let timeout = timeoutSeconds
        return try await withCheckedThrowingContinuation { continuation in
            let gate = ResumeGate(continuation: continuation)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if let workingDirectory {
                process.currentDirectoryURL = workingDirectory
            }

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()

                    // Concurrent drains — avoid classic pipe-buffer deadlock.
                    let pair = DispatchGroup()
                    let boxes = PipeDataBoxes()

                    pair.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        boxes.stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                        pair.leave()
                    }
                    pair.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        boxes.stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                        pair.leave()
                    }

                    pair.wait()
                    process.waitUntilExit()

                    let result = ProcessRunResult(
                        exitCode: process.terminationStatus,
                        stdout: String(data: boxes.stdout, encoding: .utf8) ?? "",
                        stderr: String(data: boxes.stderr, encoding: .utf8) ?? ""
                    )
                    gate.resume(returning: result)
                } catch {
                    gate.resume(throwing: error)
                }
            }

            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    process.terminate()
                }
                gate.resume(throwing: LocalProcessRunnerError.timedOut(seconds: timeout))
            }
        }
    }
}

/// One-shot resume so timeout + completion never double-resume the continuation.
private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ProcessRunResult, Error>?

    init(continuation: CheckedContinuation<ProcessRunResult, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: ProcessRunResult) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(throwing: error)
    }
}

/// Thread-safe pipe capture boxes (filled on concurrent drain queues).
private final class PipeDataBoxes: @unchecked Sendable {
    var stdout = Data()
    var stderr = Data()
}

/// 🌟 RetrievalServiceError — rare hard failures (hot store only); vault issues degrade instead.
public enum RetrievalServiceError: Error, LocalizedError, Sendable, Equatable {
    case storage(AnimaStorageError)
    case emptyQuery

    public var errorDescription: String? {
        switch self {
        case .storage(let underlying):
            return underlying.errorDescription
        case .emptyQuery:
            return "🌩️ recall_memory needs at least one filter or a text needle — the lantern cannot search the void."
        }
    }

    // 🧮 Explicit Equatable — keeps synthesis honest across Error + associated storage.
    public static func == (lhs: RetrievalServiceError, rhs: RetrievalServiceError) -> Bool {
        switch (lhs, rhs) {
        case (.emptyQuery, .emptyQuery):
            return true
        case (.storage(let a), .storage(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Retrieval Service

/// 🌟 RetrievalService — primary `recall_memory` surface.
///
/// Strategy: SwiftData hot store first (tags/project/date/visibility + text) →
/// optional vault ripgrep via injectable `ProcessRunning` → merge/rank.
/// Qdrant and Ladybug are **never** required for success.
@available(macOS 14.0, iOS 17.0, *)
public actor RetrievalService {
    private let container: SwiftDataContainer
    private let vaultURL: URL?
    private let processRunner: any ProcessRunning
    private let ripgrepExecutable: String
    private let fileManager: FileManager

    /// 🔮 Bind the librarian to a hot vault and optional Obsidian path.
    /// - Parameters:
    ///   - container: Actor-isolated SwiftData hot store.
    ///   - vaultURL: Optional SecondBrain (or fixture) root; missing → degrade vault stage.
    ///   - processRunner: Injectable runner (mock in tests; `LocalProcessRunner` in prod).
    ///   - ripgrepExecutable: Path to `rg` binary.
    ///   - fileManager: Injected for vault-existence checks.
    public init(
        container: SwiftDataContainer,
        vaultURL: URL? = nil,
        processRunner: any ProcessRunning = LocalProcessRunner(),
        ripgrepExecutable: String = "/opt/homebrew/bin/rg",
        fileManager: FileManager = .default
    ) {
        self.container = container
        self.vaultURL = vaultURL
        self.processRunner = processRunner
        self.ripgrepExecutable = ripgrepExecutable
        self.fileManager = fileManager
    }

    /// 🔍 recall_memory — hot store first, optional vault ripgrep fallback, never Qdrant/Ladybug.
    @discardableResult
    public func recallMemory(_ query: RecallQuery) async throws -> RecallResult {
        guard hasSearchableCriteria(query) else {
            throw RetrievalServiceError.emptyQuery
        }

        print("🌐 ✨ RECALL_MEMORY AWAKENS! limit=\(query.limit) vaultFallback=\(query.includeVaultFallback)")

        // 🎨 Act I — query the hot ledger with structured filters
        let hotHits = try await searchHotStore(query)
        print("🎪 📦 Hot store returned \(hotHits.count) glowing neurons")

        var vaultHits: [MemoryHit] = []
        var vaultDegraded = false
        var degradationReason: String?

        let textNeedle = query.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let shouldProbeVault = query.includeVaultFallback
            && hotHits.count < query.limit
            && !textNeedle.isEmpty

        if shouldProbeVault {
            // ✨ Act II — optional ripgrep pilgrimage into the curated vault
            let vaultOutcome = await searchVault(query: query)
            vaultHits = vaultOutcome.hits
            vaultDegraded = vaultOutcome.degraded
            degradationReason = vaultOutcome.reason
            if vaultDegraded {
                print("🌙 ⚠️ Gentle reminder: vault stage degraded — \(degradationReason ?? "unknown")")
            } else {
                print("💎 Vault ripgrep crystallized \(vaultHits.count) markdown echoes")
            }
        }

        // 🌟 Act III — merge, dedupe, rank; hot store wins identity collisions
        let merged = mergeAndRank(hot: hotHits, vault: vaultHits, limit: query.limit)
        print("🎉 ✨ RECALL_MEMORY MASTERPIECE COMPLETE! hits=\(merged.count)")

        return RecallResult(
            hits: merged,
            hotHitCount: hotHits.count,
            vaultHitCount: vaultHits.count,
            vaultDegraded: vaultDegraded,
            degradationReason: degradationReason
        )
    }

    // MARK: - Hot Store

    /// 🧮 True when the query carries at least one searchable dimension.
    private func hasSearchableCriteria(_ query: RecallQuery) -> Bool {
        let hasText = !(query.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasTags = !(query.tags?.isEmpty ?? true)
        return hasText
            || hasTags
            || query.project != nil
            || query.visibility != nil
            || query.dateFrom != nil
            || query.dateTo != nil
    }

    /// 🔍 Filter the SwiftData hot store by project/visibility/tags/date/text.
    private func searchHotStore(_ query: RecallQuery) async throws -> [MemoryHit] {
        let snapshots: [AnimaEpisodicRecordSnapshot]
        do {
            // Prefer structured project/visibility when present; finish filtering in-process.
            if query.project != nil || query.visibility != nil {
                snapshots = try await container.fetchWithFilters(
                    project: query.project,
                    agent: nil,
                    visibility: query.visibility
                )
            } else {
                snapshots = try await container.fetchAll()
            }
        } catch let storageError as AnimaStorageError {
            throw RetrievalServiceError.storage(storageError)
        } catch {
            throw RetrievalServiceError.storage(.fetchFailed(error.localizedDescription))
        }

        let needle = query.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let requiredTags = query.tags ?? []

        let filtered = snapshots.filter { record in
            if let dateFrom = query.dateFrom, record.createdAt < dateFrom { return false }
            if let dateTo = query.dateTo, record.createdAt > dateTo { return false }

            if !requiredTags.isEmpty {
                let recordTags = Set(record.tags.map { $0.lowercased() })
                let needed = requiredTags.map { $0.lowercased() }
                if !needed.allSatisfy({ recordTags.contains($0) }) {
                    return false
                }
            }

            if let needle, !needle.isEmpty {
                let haystack = record.narrative.lowercased()
                let tagHaystack = record.tags.joined(separator: " ").lowercased()
                let projectHaystack = record.project.lowercased()
                if !haystack.contains(needle)
                    && !tagHaystack.contains(needle)
                    && !projectHaystack.contains(needle) {
                    return false
                }
            }

            return true
        }

        return filtered.map { record in
            MemoryHit(
                id: record.id,
                memoryID: record.id,
                contentHash: record.contentHash,
                narrative: record.narrative,
                project: record.project,
                visibility: record.visibility,
                tags: record.tags,
                createdAt: record.createdAt,
                path: record.materializedPath,
                source: .hotStore,
                score: scoreHotRecord(record, query: query)
            )
        }
        .sorted { $0.score > $1.score }
    }

    /// 🌟 Score a hot record: recency + text/tag boosts (higher = better).
    private func scoreHotRecord(_ record: AnimaEpisodicRecordSnapshot, query: RecallQuery) -> Double {
        var score = record.createdAt.timeIntervalSince1970 / 1_000_000_000.0

        if let needle = query.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !needle.isEmpty {
            if record.narrative.lowercased().contains(needle) {
                score += 10
            }
            if record.tags.contains(where: { $0.lowercased().contains(needle) }) {
                score += 4
            }
            if record.project.lowercased().contains(needle) {
                score += 2
            }
        }

        if let tags = query.tags {
            let matched = tags.filter { wanted in
                record.tags.contains { $0.caseInsensitiveCompare(wanted) == .orderedSame }
            }
            score += Double(matched.count) * 3
        }

        // Prefer hot store over vault at equal relevance
        score += 100
        return score
    }

    // MARK: - Vault Ripgrep

    private struct VaultSearchOutcome: Sendable {
        let hits: [MemoryHit]
        let degraded: Bool
        let reason: String?
    }

    /// 🌐 Optional vault search — degrade (empty hits + flag) when path missing or ripgrep fails.
    private func searchVault(query: RecallQuery) async -> VaultSearchOutcome {
        guard let vaultURL else {
            return VaultSearchOutcome(
                hits: [],
                degraded: true,
                reason: "vault URL not configured"
            )
        }

        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: vaultURL.path, isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue else {
            return VaultSearchOutcome(
                hits: [],
                degraded: true,
                reason: "vault missing at \(vaultURL.path)"
            )
        }

        let needle = query.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !needle.isEmpty else {
            return VaultSearchOutcome(hits: [], degraded: false, reason: nil)
        }

        // rg --json -i -n --glob '*.md' <needle> <vault>
        // Keep per-file match cap modest — common needles like "test" otherwise flood pipes.
        let arguments = [
            "--json",
            "-i",
            "-n",
            "--glob", "*.md",
            "--max-count", "8",
            "--max-filesize", "512K",
            needle,
            vaultURL.path
        ]

        do {
            let run = try await processRunner.run(
                executable: ripgrepExecutable,
                arguments: arguments,
                workingDirectory: vaultURL
            )
            // rg exit 1 = no matches (success, empty); 2 = error
            if run.exitCode == 2 {
                return VaultSearchOutcome(
                    hits: [],
                    degraded: true,
                    reason: "ripgrep exit 2: \(run.stderr.prefix(200))"
                )
            }
            let hits = parseRipgrepJSONLines(run.stdout, limit: query.limit, needle: needle)
            return VaultSearchOutcome(hits: hits, degraded: false, reason: nil)
        } catch {
            return VaultSearchOutcome(
                hits: [],
                degraded: true,
                reason: "ripgrep runner failed: \(error.localizedDescription)"
            )
        }
    }

    /// 🧙 Parse ripgrep `--json` match lines into MemoryHit shards.
    private func parseRipgrepJSONLines(_ stdout: String, limit: Int, needle: String) -> [MemoryHit] {
        var hits: [MemoryHit] = []
        let lines = stdout.split(whereSeparator: \.isNewline)

        for line in lines {
            guard hits.count < limit else { break }
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["type"] as? String,
                  type == "match",
                  let dataObj = object["data"] as? [String: Any],
                  let pathObj = dataObj["path"] as? [String: Any],
                  let pathText = pathObj["text"] as? String,
                  let linesObj = dataObj["lines"] as? [String: Any],
                  let lineText = linesObj["text"] as? String
            else {
                continue
            }

            let trimmed = lineText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            var score = 1.0
            if trimmed.lowercased().contains(needle.lowercased()) {
                score += 5
            }

            hits.append(
                MemoryHit(
                    narrative: trimmed,
                    path: pathText,
                    source: .vault,
                    score: score
                )
            )
        }

        return hits
    }

    // MARK: - Merge

    /// 💎 Merge hot + vault hits; hot IDs/contentHashes win; rank by score desc.
    private func mergeAndRank(hot: [MemoryHit], vault: [MemoryHit], limit: Int) -> [MemoryHit] {
        var seenHashes = Set<String>()
        var seenPaths = Set<String>()
        var merged: [MemoryHit] = []

        for hit in hot {
            if let hash = hit.contentHash {
                seenHashes.insert(hash)
            }
            if let path = hit.path {
                seenPaths.insert(path)
            }
            merged.append(hit)
        }

        for hit in vault {
            if let hash = hit.contentHash, seenHashes.contains(hash) {
                continue
            }
            if let path = hit.path, seenPaths.contains(path) {
                continue
            }
            if let path = hit.path {
                seenPaths.insert(path)
            }
            merged.append(hit)
        }

        return Array(
            merged
                .sorted { $0.score > $1.score }
                .prefix(limit)
        )
    }
}
