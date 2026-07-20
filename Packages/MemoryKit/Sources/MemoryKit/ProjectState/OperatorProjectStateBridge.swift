/**
 * 🎭 The OperatorProjectStateBridge - Curtain Call for Linear∪Multica
 *
 * "Operators may peer behind the velvet; clients never do.
 * Live HTTP/CLI adapters merge tracker ghosts into brand-neutral
 * ProjectState — create fans Linear→Multica; update patches both."
 *
 * - The Theatrical Operator Virtuoso of Hidden Fabric
 */

import CryptoKit
import Foundation

// MARK: - Operator provider protocols (never client-facing)

/// 🌟 Linear-shaped issue fragment for the operator bridge (never client-facing).
public struct LinearIssueFragment: Sendable, Equatable {
    public var id: String
    public var title: String
    public var state: String

    public init(id: String, title: String, state: String) {
        self.id = id
        self.title = title
        self.state = state
    }
}

/// 🌟 Multica-shaped issue fragment for the operator bridge (never client-facing).
public struct MulticaIssueFragment: Sendable, Equatable {
    public var id: String
    public var title: String
    public var status: String

    public init(id: String, title: String, status: String) {
        self.id = id
        self.title = title
        self.status = status
    }
}

/// 🔮 Operator Linear provider — GraphQL adapter or mocks.
public protocol LinearProjectProvider: Sendable {
    func fetchIssues() async throws -> [LinearIssueFragment]
    func createIssue(title: String, description: String?) async throws -> LinearIssueFragment
    func updateIssue(id: String, title: String?, state: String?) async throws -> LinearIssueFragment
}

/// 🔮 Operator Multica provider — Habitat HTTP/CLI adapter or mocks.
public protocol MulticaProjectProvider: Sendable {
    func fetchIssues() async throws -> [MulticaIssueFragment]
    func createIssue(title: String, description: String?) async throws -> MulticaIssueFragment
    func updateIssue(id: String, title: String?, status: String?) async throws -> MulticaIssueFragment
}

/// 🌙 Null providers — refuse to invent green fabric until wired.
public struct NullLinearProjectProvider: LinearProjectProvider {
    public init() {}
    public func fetchIssues() async throws -> [LinearIssueFragment] {
        throw ProjectStateError.bridgeNotWired
    }
    public func createIssue(title: String, description: String?) async throws -> LinearIssueFragment {
        throw ProjectStateError.bridgeNotWired
    }
    public func updateIssue(id: String, title: String?, state: String?) async throws -> LinearIssueFragment {
        throw ProjectStateError.bridgeNotWired
    }
}

public struct NullMulticaProjectProvider: MulticaProjectProvider {
    public init() {}
    public func fetchIssues() async throws -> [MulticaIssueFragment] {
        throw ProjectStateError.bridgeNotWired
    }
    public func createIssue(title: String, description: String?) async throws -> MulticaIssueFragment {
        throw ProjectStateError.bridgeNotWired
    }
    public func updateIssue(id: String, title: String?, status: String?) async throws -> MulticaIssueFragment {
        throw ProjectStateError.bridgeNotWired
    }
}

// MARK: - Bridge

/**
 * 🌟 OperatorProjectStateBridge — `project.state` surface with Linear+Multica behind the curtain.
 *
 * Routing (operator-only; see `docs/ANIMA-PROJECT-LINKS.md`):
 * - list/get → merge live fragments into brand-neutral items
 * - create → Linear first (when keyed), then Multica linked to `BIN-*`
 * - update → patch Linear + Multica when provenance is known
 */
public actor OperatorProjectStateBridge: ProjectStateSurface {

    private let linear: any LinearProjectProvider
    private let multica: any MulticaProjectProvider
    private let cache: InMemoryProjectStateStore
    private let projectID: ProjectStateID
    private let projectTitle: String
    /// 💎 Operator-only map from opaque client item IDs → tracker provenance
    private var provenanceByItem: [ProjectStateItemID: ProjectStateProvenance] = [:]

    public init(
        linear: any LinearProjectProvider = NullLinearProjectProvider(),
        multica: any MulticaProjectProvider = NullMulticaProjectProvider(),
        projectID: ProjectStateID = ProjectStateID(rawValue: "andromeda"),
        projectTitle: String = "Andromeda",
        seed: [ProjectState] = []
    ) {
        self.linear = linear
        self.multica = multica
        self.projectID = projectID
        self.projectTitle = projectTitle
        self.cache = InMemoryProjectStateStore(seed: seed)
    }

    /// Capability: `project.state.list`
    public func listProjects() async throws -> [ProjectState] {
        try await refreshFromProviders()
        return try await cache.listProjects()
    }

    /// Capability: `project.state.get`
    public func getProject(_ id: ProjectStateID) async throws -> ProjectState {
        try await refreshFromProviders()
        return try await cache.getProject(id)
    }

    /// Capability: `project.state.create`
    ///
    /// Fan-out: Linear first (when wired) → Multica with `BIN-*` link in description.
    /// Client receives a brand-neutral `ProjectStateItem` only.
    public func createItem(_ draft: ProjectStateDraft) async throws -> ProjectStateItem {
        print("🌐 ✨ PROJECT.STATE.CREATE FAN-OUT AWAKENS!")
        var linearID: String?
        var multicaID: String?

        do {
            let created = try await linear.createIssue(
                title: draft.title,
                description: draft.notes
            )
            linearID = created.id
            print("🎪 Linear create landed as \(created.id)")
        } catch let creativeChallenge as ProjectStateError {
            if case .bridgeNotWired = creativeChallenge {
                print("🌙 ⚠️ Linear unwired — Multica-only create")
            } else {
                throw creativeChallenge
            }
        }

        let multicaDescription: String = {
            var parts: [String] = []
            if let linearID {
                parts.append("Linear: \(linearID)")
            }
            if let notes = draft.notes, !notes.isEmpty {
                parts.append(notes)
            }
            return parts.joined(separator: "\n\n")
        }()

        do {
            let created = try await multica.createIssue(
                title: draft.title,
                description: multicaDescription.isEmpty ? nil : multicaDescription
            )
            multicaID = created.id
            print("🎪 Multica create landed as \(created.id)")
        } catch let creativeChallenge as ProjectStateError {
            if case .bridgeNotWired = creativeChallenge, linearID == nil {
                // 🌩️ Both unwired — fall back to cache-local so demos still work
                print("🌙 ⚠️ Both providers unwired — cache-local create")
                return try await cache.createItem(draft)
            }
            if case .bridgeNotWired = creativeChallenge {
                print("🌙 ⚠️ Multica unwired — Linear-only create kept")
            } else {
                throw creativeChallenge
            }
        }

        // 🪄 Same salt scheme as refreshFromProviders — "create" salt made update-after-list itemNotFound.
        // Prefer Linear salt when both wired (refresh merges Multica onto the Linear-derived id).
        let itemID: ProjectStateItemID
        if let linearID {
            itemID = Self.opaqueItemID(salt: "linear", trackerID: linearID)
        } else if let multicaID {
            itemID = Self.opaqueItemID(salt: "multica", trackerID: multicaID)
        } else {
            // 🌩️ Unreachable: both-unwired already returned via cache.createItem above
            itemID = Self.opaqueItemID(salt: "multica", trackerID: UUID().uuidString)
        }
        let item = ProjectStateItem(
            id: itemID,
            title: draft.title,
            status: draft.status,
            notes: draft.notes
        )
        provenanceByItem[itemID] = ProjectStateProvenance(
            linearIssueID: linearID,
            multicaIssueID: multicaID
        )

        // ✨ Ensure project exists in cache, then append with opaque client ID
        var project: ProjectState
        if let existing = try? await cache.getProject(draft.projectID) {
            project = existing
        } else {
            project = ProjectState(id: draft.projectID, title: projectTitle, status: .active, items: [])
        }
        project.items.append(item)
        await cache.upsertProject(project)
        print("🎉 ✨ PROJECT.STATE.CREATE MASTERPIECE COMPLETE! item=\(item.id.rawValue)")
        return item
    }

    /// Capability: `project.state.update`
    ///
    /// Patch Linear + Multica when provenance is known; always update client cache.
    public func updateItem(_ id: ProjectStateItemID, _ patch: ProjectStatePatch) async throws -> ProjectStateItem {
        print("🌐 ✨ PROJECT.STATE.UPDATE FAN-OUT AWAKENS! item=\(id.rawValue)")
        let updated = try await cache.updateItem(id, patch)
        if let provenance = provenanceByItem[id] {
            if let linearID = provenance.linearIssueID {
                do {
                    _ = try await linear.updateIssue(
                        id: linearID,
                        title: patch.title,
                        state: patch.status.map(Self.linearStateName(for:))
                    )
                } catch let creativeChallenge as ProjectStateError {
                    if case .bridgeNotWired = creativeChallenge {
                        print("🌙 ⚠️ Linear update skipped (unwired)")
                    } else {
                        print("🌩️ Linear update intermission: \(creativeChallenge.localizedDescription)")
                    }
                }
            }
            if let multicaID = provenance.multicaIssueID {
                do {
                    _ = try await multica.updateIssue(
                        id: multicaID,
                        title: patch.title,
                        status: patch.status.map(Self.multicaStatusName(for:))
                    )
                } catch let creativeChallenge as ProjectStateError {
                    if case .bridgeNotWired = creativeChallenge {
                        print("🌙 ⚠️ Multica update skipped (unwired)")
                    } else {
                        print("🌩️ Multica update intermission: \(creativeChallenge.localizedDescription)")
                    }
                }
            }
        } else {
            print("🌙 ⚠️ No provenance for \(id.rawValue) — cache-only update")
        }
        print("🎉 ✨ PROJECT.STATE.UPDATE MASTERPIECE COMPLETE!")
        return updated
    }

    // MARK: - Curtain merge

    /// 🎨 Pull operator providers and materialize brand-neutral `ProjectState`.
    private func refreshFromProviders() async throws {
        let linearIssues: [LinearIssueFragment]
        let multicaIssues: [MulticaIssueFragment]

        let linearResult: Result<[LinearIssueFragment], Error>
        let multicaResult: Result<[MulticaIssueFragment], Error>
        do {
            linearResult = .success(try await linear.fetchIssues())
        } catch {
            linearResult = .failure(error)
        }
        do {
            multicaResult = .success(try await multica.fetchIssues())
        } catch {
            multicaResult = .failure(error)
        }

        switch (linearResult, multicaResult) {
        case (.failure(let left), .failure(let right)):
            if Self.isBridgeNotWired(left), Self.isBridgeNotWired(right) {
                let existing = try? await cache.listProjects()
                if let existing, !existing.isEmpty { return }
                await cache.upsertProject(
                    ProjectState(id: projectID, title: projectTitle, status: .active, items: [])
                )
                return
            }
            throw ProjectStateError.providerFailure(
                "\(left.localizedDescription); \(right.localizedDescription)"
            )
        case (.success(let left), .success(let right)):
            linearIssues = left
            multicaIssues = right
        case (.success(let left), .failure(let right)):
            if Self.isBridgeNotWired(right) {
                linearIssues = left
                multicaIssues = []
            } else {
                throw ProjectStateError.providerFailure(right.localizedDescription)
            }
        case (.failure(let left), .success(let right)):
            if Self.isBridgeNotWired(left) {
                linearIssues = []
                multicaIssues = right
            } else {
                throw ProjectStateError.providerFailure(left.localizedDescription)
            }
        }

        // ✨ Merge fragments into client-safe items — titles only, no URLs
        var items: [ProjectStateItem] = []
        var nextProvenance: [ProjectStateItemID: ProjectStateProvenance] = [:]

        for fragment in linearIssues {
            let itemID = Self.opaqueItemID(salt: "linear", trackerID: fragment.id)
            let item = ProjectStateItem(
                id: itemID,
                title: Self.stripTrackerNoise(from: fragment.title),
                status: Self.mapLinearState(fragment.state),
                notes: nil
            )
            items.append(item)
            nextProvenance[itemID] = ProjectStateProvenance(linearIssueID: fragment.id)
        }

        for fragment in multicaIssues {
            // 🪄 Prefer explicit BIN-* cross-link in Multica title/description-shaped titles
            if let linked = Self.extractLinearID(from: fragment.title),
               let matchIndex = items.firstIndex(where: {
                   nextProvenance[$0.id]?.linearIssueID == linked
               })
            {
                var prior = nextProvenance[items[matchIndex].id] ?? ProjectStateProvenance()
                prior.multicaIssueID = fragment.id
                nextProvenance[items[matchIndex].id] = prior
                continue
            }
            if let match = items.first(where: {
                $0.title.caseInsensitiveCompare(Self.stripTrackerNoise(from: fragment.title)) == .orderedSame
            }) {
                var prior = nextProvenance[match.id] ?? ProjectStateProvenance()
                prior.multicaIssueID = fragment.id
                nextProvenance[match.id] = prior
            } else {
                let itemID = Self.opaqueItemID(salt: "multica", trackerID: fragment.id)
                let item = ProjectStateItem(
                    id: itemID,
                    title: Self.stripTrackerNoise(from: fragment.title),
                    status: Self.mapMulticaStatus(fragment.status),
                    notes: nil
                )
                items.append(item)
                nextProvenance[itemID] = ProjectStateProvenance(multicaIssueID: fragment.id)
            }
        }

        provenanceByItem = nextProvenance

        let projectProvenance = ProjectStateProvenance(
            linearIssueID: linearIssues.first?.id,
            multicaIssueID: multicaIssues.first?.id
        )

        let project = ProjectState(
            id: projectID,
            title: projectTitle,
            status: .active,
            items: items,
            provenance: projectProvenance
        )
        await cache.upsertProject(project)
        print("🎉 ✨ OPERATOR BRIDGE MERGE COMPLETE! \(items.count) items behind the curtain")
    }

    /// 🪄 Deterministic opaque item id — SHA256 prefix, no tracker brand leakage.
    private static func opaqueItemID(salt: String, trackerID: String) -> ProjectStateItemID {
        let material = Data("\(salt):\(trackerID)".utf8)
        let digest = SHA256.hash(data: material)
        let hex = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return ProjectStateItemID(rawValue: "ps-\(hex)")
    }

    private static func mapLinearState(_ state: String) -> ProjectStateStatus {
        switch state.lowercased() {
        case "done", "completed", "canceled", "cancelled": return .done
        case "started", "in progress", "inprogress": return .active
        case "blocked": return .blocked
        default: return .backlog
        }
    }

    private static func mapMulticaStatus(_ status: String) -> ProjectStateStatus {
        switch status.lowercased() {
        case "done", "closed", "completed": return .done
        case "active", "in_progress", "doing", "in_review": return .active
        case "blocked": return .blocked
        default: return .backlog
        }
    }

    private static func linearStateName(for status: ProjectStateStatus) -> String {
        switch status {
        case .backlog: return "Backlog"
        case .active: return "In Progress"
        case .blocked: return "In Progress"
        case .done: return "Done"
        }
    }

    private static func multicaStatusName(for status: ProjectStateStatus) -> String {
        switch status {
        case .backlog: return "todo"
        case .active: return "in_progress"
        case .blocked: return "blocked"
        case .done: return "done"
        }
    }

    private static func isBridgeNotWired(_ error: Error) -> Bool {
        if let projectError = error as? ProjectStateError, case .bridgeNotWired = projectError {
            return true
        }
        return false
    }

    /// 🧹 Drop tracker IDs / Linear chrome from titles before they reach the client board.
    private static func stripTrackerNoise(from title: String) -> String {
        var result = title
        let patterns = [
            #"\[Linear BIN-\d+\]"#,
            #"\(BIN-\d+\)"#,
            #"\bBIN-\d+\b"#,
            #"\bHAB-\d+\b"#,
            #"\[Linear [^\]]+\]"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
            }
        }
        // ✨ Collapse leftover punctuation / whitespace from redaction
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        result = result
            .replacingOccurrences(of: "→  (", with: "(")
            .trimmingCharacters(in: CharacterSet(charactersIn: " -–—:|/"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? title : result
    }

    private static func extractLinearID(from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"BIN-\d+"#, options: []) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let swiftRange = Range(match.range, in: text)
        else {
            return nil
        }
        return String(text[swiftRange])
    }
}
