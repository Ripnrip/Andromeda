/**
 * 🎭 AndromedaMemorySession — live memory.* quill for AndromedaHome (HAB-74)
 *
 * CaptureService + RetrievalService behind the curtain. Client verbs stay
 * memory.recall / memory.store / memory.journal — never tracker brands.
 */

import Foundation
import MemoryKit
import Observation
import os.log

enum AndromedaMemoryLogger {
    private static let subsystem = "com.andromeda.home"
    static let core = Logger(subsystem: subsystem, category: "🧠 MemorySession")
}

/// 🌟 Stable capability IDs — clients see these, never store plumbing names.
///
/// Canonical Andromida verbs use underscore form. Dotted `memory.*` remain shims.
public enum AndromedaMemoryCapability: String, Sendable, CaseIterable {
    case memoryRecall = "memory_recall"
    case memoryRetain = "memory_retain"
    case memoryForget = "memory_forget"
    case memoryHealth = "memory_health"
    case recall = "memory.recall"
    case store = "memory.store"
    case journal = "memory.journal"
    case sessionDump = "memory.session_dump"

    public var verb: String {
        switch self {
        case .memoryRecall, .recall: return "recall"
        case .memoryRetain, .store: return "store"
        case .memoryForget: return "forget"
        case .memoryHealth: return "health"
        case .journal, .sessionDump: return "journal"
        }
    }
}

/// 🌟 Parsed home console command.
public enum AndromedaMemoryCommand: Equatable, Sendable {
    case recall(query: String)
    case store(narrative: String)
    case retain(narrative: String)
    case forget(target: String)
    case health
    case journal(body: String)

    public static func parse(_ raw: String) -> AndromedaMemoryCommand? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()

        if lower.hasPrefix("memory_retain ") || lower == "memory_retain"
            || lower.hasPrefix("retain ") || lower == "retain"
        {
            let prefix = lower.hasPrefix("memory_retain") ? "memory_retain" : "retain"
            let rest = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return .retain(narrative: rest)
        }
        if lower.hasPrefix("memory_forget ") || lower == "memory_forget"
            || lower.hasPrefix("forget ") || lower == "forget"
        {
            let prefix = lower.hasPrefix("memory_forget") ? "memory_forget" : "forget"
            let rest = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return .forget(target: rest)
        }
        if lower == "memory_health" || lower == "health" {
            return .health
        }
        if lower.hasPrefix("memory_recall ") || lower == "memory_recall" {
            let rest = String(trimmed.dropFirst("memory_recall".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return .recall(query: rest)
        }
        if lower.hasPrefix("recall ") || lower == "recall" {
            return .recall(query: String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if lower.hasPrefix("store ") || lower == "store" {
            return .store(narrative: String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if lower.hasPrefix("journal ") || lower == "journal" {
            return .journal(body: String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if lower.hasPrefix("session dump ") || lower == "session dump" || lower.hasPrefix("sessiondump ") {
            let rest: String
            if lower.hasPrefix("session dump") {
                rest = String(trimmed.dropFirst("session dump".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                rest = String(trimmed.dropFirst("sessiondump".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return .journal(body: rest)
        }
        return nil
    }

    public var capability: AndromedaMemoryCapability {
        switch self {
        case .recall: return .memoryRecall
        case .retain: return .memoryRetain
        case .forget: return .memoryForget
        case .health: return .memoryHealth
        case .store: return .store
        case .journal: return .journal
        }
    }
}

/// 🌟 Outcome tray for the home memory console.
public enum AndromedaMemoryOutcome: Equatable, Sendable {
    case idle
    case syncing
    case recalled(hits: [AndromedaMemoryHit], degraded: Bool, note: String?)
    case stored(idSummary: String)
    case journaled(idSummary: String)
    case empty(message: String)
    case failed(message: String)
}

public struct AndromedaMemoryHit: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let subtitle: String
    public let sourceLabel: String
    public let visibility: String?

    public init(
        id: UUID,
        title: String,
        subtitle: String,
        sourceLabel: String,
        visibility: String?
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.sourceLabel = sourceLabel
        self.visibility = visibility
    }
}

/// 🎭 Live MemoryKit session owned by AndromedaHome.
@MainActor
@Observable
public final class AndromedaMemorySession {
    public var lastOutcome: AndromedaMemoryOutcome = .idle
    public private(set) var isReady: Bool = false
    public var activeVisibility: VisibilityLevel = .private

    private var container: SwiftDataContainer?
    private var capture: CaptureService?
    private var retrieval: RetrievalService?
    private let vaultURL: URL
    private let storeURL: URL

    public init(
        vaultPath: String = ("~/Developer/SecondBrain" as NSString).expandingTildeInPath,
        storePath: String? = nil
    ) {
        self.vaultURL = URL(fileURLWithPath: vaultPath, isDirectory: true)
        let defaultStore = ("~/.multibrain/anima-hot.store" as NSString).expandingTildeInPath
        self.storeURL = URL(fileURLWithPath: storePath ?? defaultStore)
    }

    /// 🚀 Boot SwiftData hot store + Capture/Retrieval (same path MultibrainBar uses).
    public func start() async {
        do {
            let parent = storeURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            let container = try SwiftDataContainer.createOnDisk(at: storeURL)
            self.container = container
            self.capture = CaptureService(container: container)
            self.retrieval = RetrievalService(
                container: container,
                vaultURL: vaultURL,
                processRunner: LocalProcessRunner(),
                ripgrepExecutable: "/opt/homebrew/bin/rg"
            )
            isReady = true
            AndromedaMemoryLogger.core.info("🎉 ✨ ANDROMEDA MEMORY SESSION AWAKENS")
        } catch {
            isReady = false
            lastOutcome = .failed(message: "Memory store unavailable")
            AndromedaMemoryLogger.core.error("💥 Memory session boot failed: \(error.localizedDescription)")
        }
    }

    /// ⚡️ Dispatch a parsed memory.* command against live Capture/Retrieval.
    public func execute(_ command: AndromedaMemoryCommand) async {
        guard isReady, let capture, let retrieval else {
            lastOutcome = .failed(message: "Memory session not ready")
            return
        }

        lastOutcome = .syncing
        switch command {
        case .recall(let query):
            await runRecall(query: query, retrieval: retrieval)
        case .store(let narrative):
            await runStore(narrative: narrative, capture: capture, capability: .store)
        case .retain(let narrative):
            await runStore(narrative: narrative, capture: capture, capability: .memoryRetain)
        case .forget(let target):
            let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                lastOutcome = .empty(message: "Type memory_forget <memory-id>")
            } else {
                lastOutcome = .empty(message: "memory_forget accepted for \(trimmed) — curtain tombstone path 🚧")
            }
        case .health:
            lastOutcome = .empty(message: "memory_health — open Andromida Companion for outbox/drift")
        case .journal(let body):
            await runStore(
                narrative: body.isEmpty ? Self.defaultJournalBody() : body,
                capture: capture,
                capability: .journal,
                tags: ["journal", "session-dump"],
                provenance: AndromedaMemoryCapability.sessionDump.rawValue
            )
        }
    }

    // MARK: - Private

    private func runRecall(query: String, retrieval: RetrievalService) async {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            lastOutcome = .empty(message: "Type recall <query> to search memories")
            return
        }

        AndromedaMemoryLogger.core.info("🌐 ✨ \(AndromedaMemoryCapability.recall.rawValue) AWAKENS")
        do {
            let result = try await retrieval.recallMemory(
                RecallQuery(text: needle, limit: 12, includeVaultFallback: true)
            )
            let rows = result.hits.map { hit -> AndromedaMemoryHit in
                let title = hit.narrative.trimmingCharacters(in: .whitespacesAndNewlines)
                let clipped = title.count > 120 ? String(title.prefix(117)) + "…" : title
                let sourceLabel: String = {
                    switch hit.source {
                    case .hotStore: return "hot"
                    case .vault: return "vault"
                    }
                }()
                let subtitleParts = [
                    hit.project,
                    hit.path.map { shortPath($0) }
                ].compactMap { $0 }
                return AndromedaMemoryHit(
                    id: hit.id,
                    title: clipped.isEmpty ? "(empty)" : clipped,
                    subtitle: subtitleParts.joined(separator: " · "),
                    sourceLabel: sourceLabel,
                    visibility: hit.visibility
                )
            }

            if rows.isEmpty {
                lastOutcome = .empty(message: "No memories matched “\(needle)”")
            } else {
                let note: String? = result.vaultDegraded ? "Vault fallback limited" : nil
                _ = result.degradationReason
                lastOutcome = .recalled(hits: rows, degraded: result.vaultDegraded, note: note)
            }
            AndromedaMemoryLogger.core.info("🎉 ✨ \(AndromedaMemoryCapability.recall.rawValue) COMPLETE hits=\(rows.count)")
        } catch {
            lastOutcome = .failed(message: error.localizedDescription)
            AndromedaMemoryLogger.core.error("💥 recall failed: \(error.localizedDescription)")
        }
    }

    private func runStore(
        narrative: String,
        capture: CaptureService,
        capability: AndromedaMemoryCapability,
        tags: [String] = [],
        provenance: String? = nil
    ) async {
        let body = narrative.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            lastOutcome = .empty(message: "Type \(capability.verb) <text> to capture")
            return
        }

        let resolvedVisibility = VisibilityFilter.determineVisibility(
            for: body,
            suggestedVisibility: activeVisibility.rawValue,
            tags: tags
        )
        if let level = VisibilityLevel(rawValue: resolvedVisibility) {
            activeVisibility = level
        }

        AndromedaMemoryLogger.core.info("🌐 ✨ \(capability.rawValue) AWAKENS")
        do {
            let id = try await capture.storeMemory(
                narrative: body,
                project: "andromeda-home",
                agent: "andromeda-home",
                provenance: provenance ?? capability.rawValue,
                visibility: resolvedVisibility,
                tags: tags
            )
            let summary = String(id.uuidString.prefix(8))
            switch capability {
            case .journal, .sessionDump:
                lastOutcome = .journaled(idSummary: summary)
            default:
                lastOutcome = .stored(idSummary: summary)
            }
            AndromedaMemoryLogger.core.info("🎉 ✨ \(capability.rawValue) COMPLETE id=\(summary)")
        } catch {
            lastOutcome = .failed(message: error.localizedDescription)
            AndromedaMemoryLogger.core.error("💥 store failed: \(error.localizedDescription)")
        }
    }

    private static func defaultJournalBody() -> String {
        let stamp = ISO8601DateFormatter().string(from: Date())
        return "Session dump \(stamp) — captured from AndromedaHome (\(AndromedaMemoryCapability.sessionDump.rawValue))."
    }

    private func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.replacingOccurrences(of: home, with: "~")
    }
}
