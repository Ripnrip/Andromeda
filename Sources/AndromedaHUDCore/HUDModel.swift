import Foundation
import MemoryKit
import Observation
import os.log

enum HUDLogger {
    private static let subsystem = "com.andromeda.hud"
    static let core = Logger(subsystem: subsystem, category: "🧠 HUDModel")
}

/// 🌟 Stable client capability IDs — never tracker brands.
public enum HUDCapabilityID: String, Sendable {
    case recall = "memory.recall"
    case store = "memory.store"
    case journal = "memory.journal"
    case sessionDump = "memory.session_dump"
    case inferWrite = "infer.write"
    case project = "project.state"
}

/// 🌟 Parsed HUD submit verbs (store / journal / infer.write / project.state / recall).
public enum HUDCommand: Equatable, Sendable {
    case store(narrative: String)
    case journal(body: String)
    case sessionDump(body: String)
    case inferWrite(thought: String)
    /// List / filter projects (`project.state` / `project` / `project.state list`).
    case project(query: String)
    /// Create a draft item (`project.state create <title>`).
    case projectCreate(title: String)
    /// Update an item title (`project.state update <id> <title>`).
    case projectUpdate(id: String, title: String)
    case recall(query: String)

    /// 🔮 Parse leading verbs; bare text defaults to recall.
    public static func parse(_ raw: String) -> HUDCommand? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()

        if lower.hasPrefix("store ") || lower == "store" {
            let rest = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            return .store(narrative: rest)
        }
        if lower.hasPrefix("memory.journal ") || lower == "memory.journal"
            || lower.hasPrefix("journal ") || lower == "journal" {
            let prefix = lower.hasPrefix("memory.journal") ? "memory.journal" : "journal"
            let rest = String(trimmed.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .journal(body: rest)
        }
        if lower.hasPrefix("memory.session_dump ") || lower == "memory.session_dump"
            || lower.hasPrefix("session dump ") || lower == "session dump"
            || lower.hasPrefix("sessiondump ") || lower == "sessiondump" {
            let prefix: String
            if lower.hasPrefix("memory.session_dump") {
                prefix = "memory.session_dump"
            } else if lower.hasPrefix("session dump") {
                prefix = "session dump"
            } else {
                prefix = "sessiondump"
            }
            let rest = String(trimmed.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .sessionDump(body: rest)
        }
        // Prefer `infer.write` over bare `infer` so the capability ID wins.
        if lower.hasPrefix("infer.write") {
            let rest = String(trimmed.dropFirst("infer.write".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .inferWrite(thought: rest)
        }
        if lower.hasPrefix("infer ") || lower == "infer" {
            let rest = String(trimmed.dropFirst("infer".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .inferWrite(thought: rest)
        }

        // project.state create <title>  |  project create <title>
        if lower.hasPrefix("project.state create") || lower.hasPrefix("project create") {
            let prefix = lower.hasPrefix("project.state create") ? "project.state create" : "project create"
            let rest = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return .projectCreate(title: rest)
        }

        // project.state update <id> <title>  |  project update <id> <title>
        if lower.hasPrefix("project.state update") || lower.hasPrefix("project update") {
            let prefix = lower.hasPrefix("project.state update") ? "project.state update" : "project update"
            let rest = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            let id = parts.first.map(String.init) ?? ""
            let title = parts.count > 1 ? String(parts[1]) : ""
            return .projectUpdate(id: id, title: title)
        }

        if lower.hasPrefix("project.state") || lower.hasPrefix("project ") || lower == "project" {
            let prefixLen = lower.hasPrefix("project.state") ? "project.state".count : "project".count
            let rest = String(trimmed.dropFirst(prefixLen)).trimmingCharacters(in: .whitespacesAndNewlines)
            let restLower = rest.lowercased()
            // Bare verbs with no args still route to mutate (empty → hint).
            if restLower == "create" {
                return .projectCreate(title: "")
            }
            if restLower == "update" {
                return .projectUpdate(id: "", title: "")
            }
            return .project(query: rest)
        }
        if lower.hasPrefix("recall ") || lower == "recall" {
            let rest = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            return .recall(query: rest)
        }
        return .recall(query: trimmed)
    }

    public var capabilityID: HUDCapabilityID {
        switch self {
        case .store: return .store
        case .journal: return .journal
        case .sessionDump: return .sessionDump
        case .inferWrite: return .inferWrite
        case .project, .projectCreate, .projectUpdate: return .project
        case .recall: return .recall
        }
    }
}

public enum HUDOutcome: Equatable, Sendable {
    case idle
    case syncing
    case recalled(hits: [MemoryHit])
    case stored(idSummary: String)
    case journaled(idSummary: String)
    /// 🌐 Capability `project.state.list` result — titles/status only, no tracker brands.
    case projects(states: [ProjectState])
    /// ✨ Capability `project.state.create` confirmation.
    case created(title: String)
    /// ✨ Capability `project.state.update` confirmation.
    case updated(title: String)
    case empty(message: String)
    case failed(message: String)

    /// Whether the frosted results panel should appear below search.
    public var showsResultsPanel: Bool {
        switch self {
        case .idle:
            return false
        case .syncing, .recalled, .projects, .stored, .journaled, .created, .updated, .empty, .failed:
            return true
        }
    }
}

/// Compact fleet pulse for the HUD chip (headline only — no roster).
public struct HUDFleetPulse: Equatable, Sendable {
    public var status: FleetHealthStatus
    public var attentionCount: Int
    public var detail: String

    public init(
        status: FleetHealthStatus = .unknown,
        attentionCount: Int = 0,
        detail: String = "fleet idle"
    ) {
        self.status = status
        self.attentionCount = attentionCount
        self.detail = detail
    }

    public static func from(report: FleetObserveReport) -> HUDFleetPulse {
        let attention = report.attentionRows.count
        let status: FleetHealthStatus = {
            if report.attentionRows.contains(where: { $0.attention == .critical }) {
                return .red
            }
            if !report.attentionRows.isEmpty {
                return .yellow
            }
            return report.health.status
        }()
        let detail = report.headlineWhy
            ?? "Fleet pulse \(report.health.status.rawValue) · \(attention) attention(s)"
        return HUDFleetPulse(status: status, attentionCount: attention, detail: detail)
    }
}

@MainActor
@Observable
public final class HUDModel {
    public var lastOutcome: HUDOutcome = .idle
    public private(set) var isReady: Bool = false

    /// Last N submitted queries (shown when field empty + expanded).
    public private(set) var recentQueries: [String] = []

    /// Transient UX after Enter on a recall hit (open path / copy narrative).
    public var activationFeedback: String?

    /// Compact fleet-observe / health pulse for the HUD chip.
    public var fleetPulse: HUDFleetPulse = HUDFleetPulse()

    /// 🔮 Capability surface for `project.state.*` — live Studio bridge by default.
    public private(set) var projectSurface: any ProjectStateSurface

    /// UserDefaults key for persisted recent queries — exposed for test isolation.
    public static let recentQueriesDefaultsKey = "andromeda.hud.recentQueries"
    private static let recentQueriesLimit = 8

    @ObservationIgnored private var container: SwiftDataContainer?
    @ObservationIgnored private var capture: CaptureService?
    @ObservationIgnored private var retrieval: RetrievalService?
    @ObservationIgnored private var feedbackClearTask: Task<Void, Never>?
    /// Bumped on each submit / cancel so stale recalls cannot leave `.syncing` forever.
    @ObservationIgnored private var submitGeneration: UInt64 = 0

    /// Hard wall-clock budget for any submit (recall / store / project.state).
    public var submitTimeoutNanoseconds: UInt64 = 2_500_000_000

    /// - Parameters:
    ///   - projectSurface: Capability surface for `project.state.*` (defaults to live Studio bridge).
    ///   - memorySessionReady: When `true`, skips on-disk MemoryKit boot in `.task` — use for
    ///     unit/perf tests so SwiftUI appearance does not retain the model via `start()`.
    ///   - recentQueries: When non-`nil`, seeds the in-memory list and skips UserDefaults load
    ///     (snapshot / unit fixtures). Pass `[]` for an empty hermetic slate.
    public init(
        projectSurface: (any ProjectStateSurface)? = nil,
        memorySessionReady: Bool = false,
        recentQueries: [String]? = nil
    ) {
        self.projectSurface = projectSurface ?? ProjectStateBridgeFactory.makeStudioBridge()
        if let recentQueries {
            self.recentQueries = Array(recentQueries.prefix(Self.recentQueriesLimit))
        } else {
            self.recentQueries = Self.loadRecentQueries()
        }
        self.isReady = memorySessionReady
    }

    /// Clears persisted recent queries — call from test setUp/tearDown for hermetic snapshots.
    public static func clearPersistedRecentQueries() {
        UserDefaults.standard.removeObject(forKey: recentQueriesDefaultsKey)
    }

    public func start() async {
        do {
            try Task.checkCancellation()
            let defaultStore = ("~/.multibrain/anima-hot.store" as NSString).expandingTildeInPath
            let storeURL = URL(fileURLWithPath: defaultStore)
            let vaultPath = ("~/Developer/SecondBrain" as NSString).expandingTildeInPath
            let vaultURL = URL(fileURLWithPath: vaultPath, isDirectory: true)

            let parent = storeURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

            try Task.checkCancellation()
            let container = try SwiftDataContainer.createOnDisk(at: storeURL)
            try Task.checkCancellation()
            self.container = container
            self.capture = CaptureService(container: container)
            self.retrieval = RetrievalService(
                container: container,
                vaultURL: vaultURL,
                processRunner: LocalProcessRunner(),
                ripgrepExecutable: "/opt/homebrew/bin/rg"
            )
            isReady = true
            refreshFleetPulse()
            HUDLogger.core.info("🎉 ✨ HUD MEMORY SESSION AWAKENS")
        } catch is CancellationError {
            shutdown()
            HUDLogger.core.info("🌙 HUD session boot cancelled")
        } catch {
            isReady = false
            lastOutcome = .failed(message: "Memory store unavailable")
            HUDLogger.core.error("💥 HUD session boot failed: \(error.localizedDescription)")
        }
    }

    /// Drop session services and cancel in-flight work so the model can deallocate.
    public func shutdown() {
        cancelInFlightWork()
        feedbackClearTask?.cancel()
        feedbackClearTask = nil
        capture = nil
        retrieval = nil
        container = nil
        isReady = false
        lastOutcome = .idle
        activationFeedback = nil
    }

    #if DEBUG
    /// Test seam — inject a deterministic capture/retrieval session so integration and
    /// snapshot tests can drive the real `submitQuery` → recall/store → `applyOutcome`
    /// pipeline against an in-memory store (no on-disk boot, no live vault ripgrep).
    /// Never called in production; the real session is built in `start()`.
    func injectSessionForTesting(retrieval: RetrievalService, capture: CaptureService? = nil) {
        self.retrieval = retrieval
        if let capture {
            self.capture = capture
        }
        isReady = true
    }
    #endif

    /// 👁️ Compact FleetObserveComposer pulse (local health.json × launchctl — no paid paths).
    public func refreshFleetPulse() {
        let report = FleetObserveComposer.observeLive(observingHostRole: .hub)
        fleetPulse = HUDFleetPulse.from(report: report)
    }

    public func submitQuery(_ query: String, recordRecent: Bool = true) async {
        guard let command = HUDCommand.parse(query) else { return }

        if recordRecent {
            recordRecentQuery(query)
        }

        submitGeneration &+= 1
        let token = submitGeneration
        lastOutcome = .syncing

        let timeout = submitTimeoutNanoseconds
        // Race work vs timeout via unstructured Tasks + one-shot continuation.
        // (TaskGroup { @MainActor in } trips Swift 6 region checker.)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let gate = SubmitFinishGate(continuation: continuation)

            Task { @MainActor [weak self] in
                guard let self else {
                    gate.finish()
                    return
                }
                await self.executeCommand(command, token: token)
                gate.finish()
            }

            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: timeout)
                guard let self, self.submitGeneration == token else {
                    gate.finish()
                    return
                }
                if case .syncing = self.lastOutcome {
                    self.submitGeneration &+= 1
                    self.lastOutcome = .failed(message: "Timed out — try a more specific query")
                    HUDLogger.core.error("💥 HUD submit timed out after \(timeout)ns")
                }
                gate.finish()
            }
        }
    }

    /// Cancel in-flight submit and clear Working / results without tearing down the session.
    public func dismissResults() {
        submitGeneration &+= 1
        lastOutcome = .idle
        activationFeedback = nil
    }

    /// Escape / collapse: abandon Working and any pending recall.
    public func cancelInFlightWork() {
        submitGeneration &+= 1
        if case .syncing = lastOutcome {
            lastOutcome = .idle
        }
    }

    /// Apply only if this submit is still the active generation (timeout / Escape / supersede).
    private func applyOutcome(_ outcome: HUDOutcome, token: UInt64) {
        guard submitGeneration == token else { return }
        lastOutcome = outcome
    }

    private func executeCommand(_ command: HUDCommand, token: UInt64) async {
        switch command {
        case .project(let needle):
            await runProject(query: needle, token: token)
        case .projectCreate(let title):
            await runProjectCreate(title: title, token: token)
        case .projectUpdate(let id, let title):
            await runProjectUpdate(id: id, title: title, token: token)
        case .store(let narrative):
            guard isReady, let capture else {
                applyOutcome(.failed(message: "Memory session not ready"), token: token)
                return
            }
            await runStore(
                narrative: narrative,
                capture: capture,
                provenance: HUDCapabilityID.store.rawValue,
                tags: [],
                emptyHint: "store",
                isJournal: false,
                token: token
            )
        case .journal(let body):
            guard isReady, let capture else {
                applyOutcome(.failed(message: "Memory session not ready"), token: token)
                return
            }
            await runStore(
                narrative: body.isEmpty ? Self.defaultCaptureBody(for: .journal) : body,
                capture: capture,
                provenance: HUDCapabilityID.journal.rawValue,
                tags: ["journal"],
                emptyHint: "journal",
                isJournal: true,
                token: token
            )
        case .sessionDump(let body):
            guard isReady, let capture else {
                applyOutcome(.failed(message: "Memory session not ready"), token: token)
                return
            }
            await runStore(
                narrative: body.isEmpty ? Self.defaultCaptureBody(for: .sessionDump) : body,
                capture: capture,
                provenance: HUDCapabilityID.sessionDump.rawValue,
                tags: ["journal", "session-dump"],
                emptyHint: "session dump",
                isJournal: true,
                token: token
            )
        case .inferWrite(let thought):
            guard isReady, let capture else {
                applyOutcome(.failed(message: "Memory session not ready"), token: token)
                return
            }
            await runStore(
                narrative: thought,
                capture: capture,
                provenance: HUDCapabilityID.inferWrite.rawValue,
                tags: ["infer-write"],
                emptyHint: "infer.write",
                isJournal: false,
                token: token
            )
        case .recall(let needle):
            guard isReady, let retrieval else {
                applyOutcome(.failed(message: "Memory session not ready"), token: token)
                return
            }
            await runRecall(query: needle, retrieval: retrieval, token: token)
        }
    }

    public func showActivationFeedback(_ message: String) {
        activationFeedback = message
        feedbackClearTask?.cancel()
        feedbackClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.activationFeedback = nil
        }
    }

    public func recordRecentQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var next = recentQueries.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        next.insert(trimmed, at: 0)
        if next.count > Self.recentQueriesLimit {
            next = Array(next.prefix(Self.recentQueriesLimit))
        }
        recentQueries = next
        UserDefaults.standard.set(recentQueries, forKey: Self.recentQueriesDefaultsKey)
    }

    private static func loadRecentQueries() -> [String] {
        (UserDefaults.standard.array(forKey: recentQueriesDefaultsKey) as? [String]) ?? []
    }

    /// Capability: `project.state.list` — filter by project/item title when needle present.
    private func runProject(query: String, token: UInt64) async {
        HUDLogger.core.info("🌐 ✨ project.state AWAKENS")
        do {
            var projects = try await projectSurface.listProjects()
            let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !needle.isEmpty {
                projects = Self.filterProjects(projects, matching: needle)
            }
            projects = projects.map { project in
                var copy = project
                let activeItems = project.items.filter { $0.status == .active }
                let otherOpen = project.items.filter { $0.status == .backlog || $0.status == .blocked }
                let rest = project.items.filter { $0.status == .done }
                copy.items = activeItems + otherOpen + rest
                return copy
            }

            if projects.isEmpty {
                applyOutcome(.empty(message: "No projects matched — try project.state"), token: token)
            } else {
                applyOutcome(.projects(states: projects), token: token)
            }
            HUDLogger.core.info("🎉 ✨ project.state COMPLETE hits=\(projects.count)")
        } catch is CancellationError {
            return
        } catch {
            applyOutcome(
                .failed(message: "project.state.list failed: \(Self.clientSafeProjectMessage(from: error))"),
                token: token
            )
            HUDLogger.core.error("💥 project.state failed: \(error.localizedDescription)")
        }
    }

    /// Capability: `project.state.create` — draft into first listed project (client-safe copy).
    private func runProjectCreate(title: String, token: UInt64) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            applyOutcome(
                .empty(message: "project.state.create needs a title — try project.state create <title>"),
                token: token
            )
            return
        }
        HUDLogger.core.info("🌐 ✨ project.state.create AWAKENS")
        do {
            let projects = try await projectSurface.listProjects()
            guard let projectID = projects.first?.id else {
                applyOutcome(
                    .empty(message: "project.state.create needs a project — try project.state first"),
                    token: token
                )
                return
            }
            let draft = ProjectStateDraft(projectID: projectID, title: trimmed, status: .backlog)
            _ = try await projectSurface.createItem(draft)
            applyOutcome(.created(title: trimmed), token: token)
            HUDLogger.core.info("🎉 ✨ project.state.create COMPLETE")
        } catch is CancellationError {
            return
        } catch {
            applyOutcome(
                .failed(message: "project.state.create failed: \(Self.clientSafeProjectMessage(from: error))"),
                token: token
            )
            HUDLogger.core.error("💥 project.state.create failed: \(error.localizedDescription)")
        }
    }

    /// Capability: `project.state.update` — patch item title (client-safe copy).
    private func runProjectUpdate(id: String, title: String, token: UInt64) async {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            applyOutcome(
                .empty(message: "project.state.update needs an id — try project.state update <id> <title>"),
                token: token
            )
            return
        }
        guard !trimmedTitle.isEmpty else {
            applyOutcome(
                .empty(message: "project.state.update needs a title — try project.state update <id> <title>"),
                token: token
            )
            return
        }
        HUDLogger.core.info("🌐 ✨ project.state.update AWAKENS")
        do {
            let patch = ProjectStatePatch(title: trimmedTitle)
            _ = try await projectSurface.updateItem(ProjectStateItemID(rawValue: trimmedID), patch)
            applyOutcome(.updated(title: trimmedTitle), token: token)
            HUDLogger.core.info("🎉 ✨ project.state.update COMPLETE")
        } catch {
            applyOutcome(
                .failed(message: "project.state.update failed: \(Self.clientSafeProjectMessage(from: error))"),
                token: token
            )
            HUDLogger.core.error("💥 project.state.update failed: \(error.localizedDescription)")
        }
    }

    /// 🧹 Filter projects whose title or any item title contains `needle`.
    static func filterProjects(_ projects: [ProjectState], matching needle: String) -> [ProjectState] {
        projects.compactMap { project in
            let titleHit = project.title.lowercased().contains(needle)
            let matchingItems = project.items.filter { $0.title.lowercased().contains(needle) }
            if titleHit {
                return project
            }
            guard !matchingItems.isEmpty else { return nil }
            var copy = project
            copy.items = matchingItems
            return copy
        }
    }

    /// 🧹 Strip accidental tracker brand leakage from error copy shown on glass.
    public static func clientSafeProjectMessage(from error: Error) -> String {
        ProjectStatePanelModel.clientSafeMessage(from: error)
    }

    private func runRecall(query: String, retrieval: RetrievalService, token: UInt64) async {
        guard !query.isEmpty else {
            applyOutcome(.empty(message: "Type a query to search memories"), token: token)
            return
        }

        do {
            let result = try await retrieval.recallMemory(
                RecallQuery(text: query, limit: 12, includeVaultFallback: true)
            )
            if result.hits.isEmpty {
                applyOutcome(.empty(message: "No memories matched “\(query)”"), token: token)
            } else {
                applyOutcome(.recalled(hits: result.hits), token: token)
            }
        } catch is CancellationError {
            // Timed out / Escape — outcome already applied by submit/cancel.
            return
        } catch {
            applyOutcome(.failed(message: error.localizedDescription), token: token)
        }
    }

    private func runStore(
        narrative: String,
        capture: CaptureService,
        provenance: String,
        tags: [String],
        emptyHint: String,
        isJournal: Bool,
        token: UInt64
    ) async {
        guard !narrative.isEmpty else {
            applyOutcome(.empty(message: "Type \(emptyHint) <text> to capture"), token: token)
            return
        }

        let resolvedVisibility = VisibilityFilter.determineVisibility(
            for: narrative,
            suggestedVisibility: VisibilityClass.private.rawValue,
            tags: tags
        )

        do {
            let id = try await capture.storeMemory(
                narrative: narrative,
                project: "andromeda-hud",
                agent: "andromeda-hud",
                provenance: provenance,
                visibility: resolvedVisibility,
                tags: tags
            )
            let summary = String(id.uuidString.prefix(8))
            applyOutcome(
                isJournal ? .journaled(idSummary: summary) : .stored(idSummary: summary),
                token: token
            )
        } catch is CancellationError {
            return
        } catch {
            applyOutcome(.failed(message: error.localizedDescription), token: token)
        }
    }

    private static func defaultCaptureBody(for capability: HUDCapabilityID) -> String {
        let stamp = ISO8601DateFormatter().string(from: Date())
        switch capability {
        case .journal:
            return "Journal entry \(stamp) — captured from AndromedaHUD (\(capability.rawValue))."
        case .sessionDump:
            return "Session dump \(stamp) — captured from AndromedaHUD (\(capability.rawValue))."
        default:
            preconditionFailure("Default capture body is only valid for journal capabilities")
        }
    }
}

/// One-shot resume so work + timeout never double-resume `submitQuery`'s continuation.
private final class SubmitFinishGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    init(continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func finish() {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume()
    }
}
