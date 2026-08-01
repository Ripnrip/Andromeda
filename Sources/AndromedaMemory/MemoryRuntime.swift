import AndromedaDomain
import AndromedaJournal
import Foundation

/// Placeholder memory runtime that keeps the Milestone 0 package graph buildable without projecting state yet.
public actor MemoryRuntime {
    private let journal: any EventJournal

    public init(journal: any EventJournal) {
        self.journal = journal
    }

    public func journalBacklogCount() async throws -> Int {
        try await journal.replay(after: nil).count
    }
}
