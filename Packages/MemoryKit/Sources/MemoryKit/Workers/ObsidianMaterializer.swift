/**
 * 🎭 The ObsidianMaterializer - The Dream Scribe of Cold Projection
 *
 * "While the hot journal sleeps in SwiftData's velvet ACID chamber,
 * this nocturnal scribe walks the vault by moonlight — pulling unmarked
 * neurons, weaving DATA-CONTRACTS §6 markdown, and stamping the path home.
 * The café never waits on the roast; store_memory stays unblocked."
 *
 * - The Spellbinding Museum Director of Dream / Consolidation
 */

import Foundation

// MARK: - Errors

/// 🌩️ Materialization storms — loud in the wings, never rewriting the hot store mid-scene
public enum ObsidianMaterializationError: Error, LocalizedError, Equatable, Sendable {
    case vaultUnwritable(String)
    case writeFailed(String)
    case storeUpdateFailed(String)

    public var errorDescription: String? {
        switch self {
        case .vaultUnwritable(let details):
            return "🌩️ Vault stage is dark: \(details)"
        case .writeFailed(let details):
            return "🌩️ Markdown quill snapped mid-verse: \(details)"
        case .storeUpdateFailed(let details):
            return "🌩️ Path stamp failed after vault write: \(details)"
        }
    }
}

// MARK: - Vault IO Port

/// 🌟 The VaultFileWriting - Injectable filesystem alchemy for fixture vaults & fail-open tests
public protocol VaultFileWriting: Sendable {
    func fileExists(at url: URL) -> Bool
    func createDirectoryIfNeeded(at url: URL) throws
    func readUTF8(from url: URL) throws -> String
    func writeUTF8(_ contents: String, to url: URL) throws
}

/// 💎 The FileSystemVaultWriter - Real disk ink for production dreams
public struct FileSystemVaultWriter: VaultFileWriting {
    public init() {}

    // 🌟 Peek whether a note already haunts this path
    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    // 🌟 Raise the Sessions chamber if it isn't standing yet
    public func createDirectoryIfNeeded(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    // 🌟 Read the existing parchment for append-merge rituals
    public func readUTF8(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ObsidianMaterializationError.writeFailed("Could not decode UTF-8 at \(url.path)")
        }
        return text
    }

    // 🌟 Commit ink atomically enough for our dream pass (overwrite with full merged text)
    public func writeUTF8(_ contents: String, to url: URL) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - Report

/// 📜 A single record's materialization fate
public struct MaterializedNoteResult: Equatable, Sendable {
    public enum Outcome: String, Equatable, Sendable {
        case written
        case merged
        case skippedDuplicate
        case failed
    }

    public let recordID: UUID
    public let contentHash: String
    public let relativePath: String?
    public let outcome: Outcome
    public let errorMessage: String?

    public init(
        recordID: UUID,
        contentHash: String,
        relativePath: String?,
        outcome: Outcome,
        errorMessage: String? = nil
    ) {
        self.recordID = recordID
        self.contentHash = contentHash
        self.relativePath = relativePath
        self.outcome = outcome
        self.errorMessage = errorMessage
    }
}

/// 🎪 Batch curtain call for one dream cycle
public struct MaterializationBatchReport: Equatable, Sendable {
    public let results: [MaterializedNoteResult]

    public var writtenCount: Int { results.filter { $0.outcome == .written }.count }
    public var mergedCount: Int { results.filter { $0.outcome == .merged }.count }
    public var failedCount: Int { results.filter { $0.outcome == .failed }.count }
    public var successPaths: [String] {
        results.compactMap { $0.outcome == .failed ? nil : $0.relativePath }
    }

    public init(results: [MaterializedNoteResult]) {
        self.results = results
    }
}

// MARK: - Materializer

/// 🎭 ObsidianMaterializer — background worker projecting hot captures into §6 session notes.
///
/// Hot-path contract: callers of `store_memory` / `SwiftDataContainer.insert` MUST NOT await
/// this actor. Failures leave `materializedPath` nil and never mutate narrative/hash fields.
@available(macOS 14.0, iOS 17.0, *)
public actor ObsidianMaterializer {
    public static let sessionsDirectoryName = "07-Sessions"
    public static let contentHashMarkerPrefix = "<!-- anima:content_hash:"
    public static let contentHashMarkerSuffix = " -->"

    private let store: SwiftDataContainer
    private let vaultRoot: URL
    private let writer: any VaultFileWriting
    private let calendar: Calendar
    private let timeZone: TimeZone

    // 🌟 The Grand Awakening — bind hot store to a (temp/fixture/production) vault root
    public init(
        store: SwiftDataContainer,
        vaultRoot: URL,
        writer: any VaultFileWriting = FileSystemVaultWriter(),
        calendar: Calendar = Calendar(identifier: .gregorian),
        timeZone: TimeZone = TimeZone(secondsFromGMT: 0) ?? .current
    ) {
        self.store = store
        self.vaultRoot = vaultRoot
        self.writer = writer
        var cal = calendar
        cal.timeZone = timeZone
        self.calendar = cal
        self.timeZone = timeZone
    }

    /// 🌙 Pull every neuron with nil `materializedPath`, project §6 markdown, stamp the path.
    /// Failures are recorded per-record; the hot store stays intact for those that stumble.
    @discardableResult
    public func materializePending() async -> MaterializationBatchReport {
        print("🌐 ✨ OBSIDIAN MATERIALIZATION AWAKENS!")

        let pending: [AnimaEpisodicRecordSnapshot]
        do {
            let all = try await store.fetchAll()
            pending = all.filter { $0.materializedPath == nil }
        } catch {
            print("💥 😭 MATERIALIZATION TEMPORARILY HALTED! Fetch failed: \(error.localizedDescription)")
            return MaterializationBatchReport(results: [])
        }

        print("🎪 📦 \(pending.count) unmarked neurons entering the dream ring!")

        var spellbindingResults: [MaterializedNoteResult] = []
        for record in pending {
            let result = await materializeOne(record)
            spellbindingResults.append(result)
        }

        let report = MaterializationBatchReport(results: spellbindingResults)
        print(
            "🎉 ✨ MATERIALIZATION MASTERPIECE COMPLETE! " +
            "written=\(report.writtenCount) merged=\(report.mergedCount) failed=\(report.failedCount)"
        )
        return report
    }

    /// 🌟 Relative vault path: `07-Sessions/YYYY-MM-DD--<project>--<agent>.md`
    public func relativeSessionPath(for record: AnimaEpisodicRecordSnapshot) -> String {
        let day = Self.dayString(for: record.createdAt, calendar: calendar, timeZone: timeZone)
        let project = Self.sanitizePathComponent(record.project)
        let agent = Self.sanitizePathComponent(record.agent)
        return "\(Self.sessionsDirectoryName)/\(day)--\(project)--\(agent).md"
    }

    /// 🎨 Render a full §6 session-learning note (frontmatter includes visibility)
    public func renderSessionNote(for record: AnimaEpisodicRecordSnapshot) -> String {
        let day = Self.dayString(for: record.createdAt, calendar: calendar, timeZone: timeZone)
        let tags = Self.normalizedTags(for: record)
        let insightLine = Self.insightBullet(for: record)

        let frontmatter = """
        ---
        type: session-learning
        created: \(day)
        date: \(day)
        agent: \(Self.yamlScalar(record.agent))
        agent_session: \(record.id.uuidString.lowercased())
        platform_source: anima
        project: \(Self.yamlScalar(record.project))
        observation_types: [discovery]
        concepts: []
        source: \(Self.yamlScalar(record.provenance))
        community: null
        tags: [\(tags.map { Self.yamlScalar($0) }.joined(separator: ", "))]
        confidence: synthesized
        visibility: \(Self.yamlScalar(record.visibility))
        content_hash: \(Self.yamlScalar(record.contentHash))
        ---
        """

        let body = """
        # \(record.project) — session learning

        ## Key Insights
        \(insightLine)

        ## What Changed
        - \(Self.escapeBullet(record.narrative))

        ## Problem → Solution
        - Captured via Andromeda hot store; projected by ObsidianMaterializer.

        ## Files Touched
        - _(none listed in episodic capture)_

        ## Connections
        - [[Sessions MOC]]

        ---
        _Materialized by Andromeda ObsidianMaterializer from content_hash `\(record.contentHash)`._
        """

        return frontmatter + "\n" + body + "\n"
    }

    /// 🌿 Append-merge a new insight into an existing §6 note without overwriting prior wisdom
    public func appendMerge(
        existingText: String,
        record: AnimaEpisodicRecordSnapshot
    ) -> (merged: String, added: Bool) {
        let marker = Self.contentHashMarker(for: record.contentHash)
        if existingText.contains(marker) {
            return (existingText, false)
        }

        let insight = Self.insightBullet(for: record)
        var lines = existingText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // Ensure visibility rides along in frontmatter on merge
        lines = Self.ensureFrontmatterVisibility(lines, visibility: record.visibility)

        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "## Key Insights" }) else {
            // Malformed note — append a fresh Key Insights block at the end rather than clobber
            let appended = existingText.trimmingCharacters(in: .whitespacesAndNewlines)
                + "\n\n## Key Insights\n\(insight)\n"
            return (appended, true)
        }

        var end = lines.count
        if start + 1 < lines.count {
            for j in (start + 1)..<lines.count {
                if lines[j].hasPrefix("## ") {
                    end = j
                    break
                }
            }
        }

        var section = Array(lines[(start + 1)..<end])
        while section.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            section.removeLast()
        }
        section.append(insight)
        section.append("")

        let head = Array(lines[0...start])
        let tail = Array(lines[end...])
        let merged = (head + section + tail).joined(separator: "\n")
        let normalized = merged.hasSuffix("\n") ? merged : merged + "\n"
        return (normalized, true)
    }

    // MARK: - Private Rites

    private func materializeOne(_ record: AnimaEpisodicRecordSnapshot) async -> MaterializedNoteResult {
        let relative = relativeSessionPath(for: record)
        let absolute = vaultRoot.appendingPathComponent(relative)

        do {
            try writer.createDirectoryIfNeeded(at: absolute.deletingLastPathComponent())

            let outcome: MaterializedNoteResult.Outcome
            if writer.fileExists(at: absolute) {
                let existing = try writer.readUTF8(from: absolute)
                let (merged, added) = appendMerge(existingText: existing, record: record)
                if added {
                    try writer.writeUTF8(merged, to: absolute)
                    outcome = .merged
                } else {
                    outcome = .skippedDuplicate
                }
            } else {
                let note = renderSessionNote(for: record)
                try writer.writeUTF8(note, to: absolute)
                outcome = .written
            }

            // Stamp path only after successful vault IO — hot fields otherwise untouched
            let stamped = AnimaEpisodicRecordSnapshot(
                id: record.id,
                contentHash: record.contentHash,
                createdAt: record.createdAt,
                project: record.project,
                agent: record.agent,
                narrative: record.narrative,
                visibility: record.visibility,
                provenance: record.provenance,
                tags: record.tags,
                materializedPath: relative
            )
            try await store.update(stamped)

            return MaterializedNoteResult(
                recordID: record.id,
                contentHash: record.contentHash,
                relativePath: relative,
                outcome: outcome
            )
        } catch {
            print("💥 😭 Materialization failed for \(record.contentHash): \(error.localizedDescription)")
            // 🛡️ Fail-open vs hot store: leave materializedPath nil; do not mutate other fields
            return MaterializedNoteResult(
                recordID: record.id,
                contentHash: record.contentHash,
                relativePath: nil,
                outcome: .failed,
                errorMessage: error.localizedDescription
            )
        }
    }

    // MARK: - Formatting Helpers

    static func dayString(for date: Date, calendar: Calendar, timeZone: TimeZone) -> String {
        var cal = calendar
        cal.timeZone = timeZone
        let parts = cal.dateComponents([.year, .month, .day], from: date)
        let y = parts.year ?? 1970
        let m = parts.month ?? 1
        let d = parts.day ?? 1
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func sanitizePathComponent(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let replaced = trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        return replaced.isEmpty ? "unknown" : replaced
    }

    static func yamlScalar(_ value: String) -> String {
        let needsQuotes = value.isEmpty
            || value.contains(where: { ":#{}[],&*?|-<>=!%@`'\"".contains($0) })
            || value.hasPrefix(" ")
            || value.hasSuffix(" ")
        if needsQuotes {
            let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return value
    }

    static func normalizedTags(for record: AnimaEpisodicRecordSnapshot) -> [String] {
        var tags = record.tags
        let sessionTag = "session/\(record.agent)"
        let projectTag = "project/\(record.project)"
        if !tags.contains(sessionTag) { tags.insert(sessionTag, at: 0) }
        if !tags.contains(projectTag) { tags.insert(projectTag, at: min(1, tags.count)) }
        return tags
    }

    static func contentHashMarker(for hash: String) -> String {
        "\(contentHashMarkerPrefix)\(hash)\(contentHashMarkerSuffix)"
    }

    static func insightBullet(for record: AnimaEpisodicRecordSnapshot) -> String {
        let text = escapeBullet(record.narrative.isEmpty ? "(empty narrative)" : record.narrative)
        return "- \(text) \(contentHashMarker(for: record.contentHash))"
    }

    static func escapeBullet(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 💅 Slip `visibility:` into YAML frontmatter if a prior note forgot the cloak tag
    static func ensureFrontmatterVisibility(_ lines: [String], visibility: String) -> [String] {
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return lines }
        var result = lines
        if let end = result.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            let hasVisibility = result[1..<end].contains { $0.lowercased().hasPrefix("visibility:") }
            if !hasVisibility {
                result.insert("visibility: \(yamlScalar(visibility))", at: end)
            }
        }
        return result
    }
}
