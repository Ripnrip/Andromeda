import Foundation
import MemoryKit
import Observation

/// 🌟 Debounced live `memory.recall` for the HUD field — skips store / infer.write / project.state verbs.
@MainActor
@Observable
public final class MemorySearchViewModel {
    public var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            scheduleLiveSearch()
        }
    }

    public private(set) var isSearching: Bool = false
    public var hudModel: HUDModel

    /// Debounce window for live recall (nanoseconds).
    public var debounceNanoseconds: UInt64 = 280_000_000

    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var generation: UInt64 = 0

    public init(hudModel: HUDModel) {
        self.hudModel = hudModel
    }

    /// Push an external TextField binding into the view model (avoids double-binding loops).
    public func updateQueryFromField(_ newValue: String) {
        guard newValue != query else { return }
        query = newValue
    }

    /// Cancel in-flight debounce (e.g. Escape / collapse) and abandon Working.
    public func cancelPendingSearch() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
        // If a live debounce already set `.syncing`, clear it when Escape cancels.
        if case .syncing = hudModel.lastOutcome {
            hudModel.cancelInFlightWork()
        }
    }

    private func scheduleLiveSearch() {
        searchTask?.cancel()
        generation &+= 1
        let token = generation

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isSearching = false
            return
        }

        // Live search only for recall — never auto-fire store / infer.write / project.state.
        guard let command = HUDCommand.parse(trimmed), case .recall(let needle) = command else {
            isSearching = false
            return
        }
        guard !needle.isEmpty else {
            isSearching = false
            return
        }

        isSearching = true
        let delay = debounceNanoseconds
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            guard let self, self.generation == token else { return }
            // Live debounce must not pollute recent-query history.
            await self.hudModel.submitQuery(trimmed, recordRecent: false)
            if self.generation == token {
                self.isSearching = false
            }
        }
    }
}
