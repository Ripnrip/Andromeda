import AndromedaDomain
import Foundation

public enum MemoryKind: String, Codable, CaseIterable, Sendable {
    case decision
    case discovery
    case workflow
    case issue
    case checkpoint
    case note
}

public enum PrivacyLevel: String, Codable, CaseIterable, Comparable, Sendable {
    case `public`
    case project
    case `private`

    public static func < (lhs: PrivacyLevel, rhs: PrivacyLevel) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .public: 0
        case .project: 1
        case .private: 2
        }
    }
}

public enum MemoryWriteStatus: String, Codable, Sendable {
    case committed
    case skipped
    case retryableFailure
}

public enum VerificationStatus: String, Codable, Sendable {
    case verified
    case pending
    case failed
    case unsupported
}

public enum MemoryRetryStatus: String, Codable, Sendable {
    case none
    case pending
}

public struct MemorySource: Codable, Equatable, Sendable {
    public let subsystem: String
    public let actor: String
    public let label: String

    public init(subsystem: String, actor: String, label: String) {
        self.subsystem = subsystem
        self.actor = actor
        self.label = label
    }
}

public struct MemoryRecord: Codable, Equatable, Sendable {
    public let memoryID: MemoryID
    public let eventID: EventID
    public let correlationID: UUID
    public let scope: EventScope
    public let source: MemorySource
    public let kind: MemoryKind
    public let privacyLevel: PrivacyLevel
    public let summary: String
    public let content: String
    public let tags: [String]
    public let metadata: [String: String]
    public let relatedContext: [String: [String]]
    public let checksum: String
    public let createdAt: Date

    public init(
        memoryID: MemoryID,
        eventID: EventID,
        correlationID: UUID,
        scope: EventScope,
        source: MemorySource,
        kind: MemoryKind,
        privacyLevel: PrivacyLevel,
        summary: String,
        content: String,
        tags: [String],
        metadata: [String: String],
        relatedContext: [String: [String]],
        checksum: String,
        createdAt: Date
    ) {
        self.memoryID = memoryID
        self.eventID = eventID
        self.correlationID = correlationID
        self.scope = scope
        self.source = source
        self.kind = kind
        self.privacyLevel = privacyLevel
        self.summary = summary
        self.content = content
        self.tags = tags
        self.metadata = metadata
        self.relatedContext = relatedContext
        self.checksum = checksum
        self.createdAt = createdAt
    }
}

public struct MemoryWriteReceipt: Codable, Equatable, Sendable {
    public let memoryID: MemoryID
    public let sinkID: String
    public let schemaVersion: String
    public let checksum: String
    public let status: MemoryWriteStatus
    public let verification: VerificationStatus

    public init(
        memoryID: MemoryID,
        sinkID: String,
        schemaVersion: String,
        checksum: String,
        status: MemoryWriteStatus,
        verification: VerificationStatus
    ) {
        self.memoryID = memoryID
        self.sinkID = sinkID
        self.schemaVersion = schemaVersion
        self.checksum = checksum
        self.status = status
        self.verification = verification
    }
}

public struct RememberIntent: Codable, Equatable, Sendable {
    public let scope: EventScope
    public let source: MemorySource
    public let content: String
    public let kind: MemoryKind
    public let privacyLevel: PrivacyLevel
    public let tags: [String]
    public let metadata: [String: String]
    public let idempotencyKey: IdempotencyKey
    public let relatedContext: [String: [String]]

    public init(
        scope: EventScope,
        source: MemorySource,
        content: String,
        kind: MemoryKind,
        privacyLevel: PrivacyLevel,
        tags: [String] = [],
        metadata: [String: String] = [:],
        idempotencyKey: IdempotencyKey,
        relatedContext: [String: [String]] = [:]
    ) {
        self.scope = scope
        self.source = source
        self.content = content
        self.kind = kind
        self.privacyLevel = privacyLevel
        self.tags = tags
        self.metadata = metadata
        self.idempotencyKey = idempotencyKey
        self.relatedContext = relatedContext
    }
}

public struct MemoryRememberResponse: Codable, Equatable, Sendable {
    public let memoryID: MemoryID
    public let eventID: EventID
    public let correlationID: UUID
    public let sinkReceipts: [MemoryWriteReceipt]
    public let verificationStatus: VerificationStatus
    public let warnings: [String]
    public let retryStatus: MemoryRetryStatus

    public init(
        memoryID: MemoryID,
        eventID: EventID,
        correlationID: UUID,
        sinkReceipts: [MemoryWriteReceipt],
        verificationStatus: VerificationStatus,
        warnings: [String],
        retryStatus: MemoryRetryStatus
    ) {
        self.memoryID = memoryID
        self.eventID = eventID
        self.correlationID = correlationID
        self.sinkReceipts = sinkReceipts
        self.verificationStatus = verificationStatus
        self.warnings = warnings
        self.retryStatus = retryStatus
    }
}

public struct RecallRequest: Codable, Equatable, Sendable {
    public let query: String
    public let purpose: String?
    public let scope: EventScope
    public let privacyCeiling: PrivacyLevel
    public let resultLimit: Int
    public let kinds: [MemoryKind]
    public let recencyWindowDays: Int?
    public let fileContext: [String]
    public let symbolContext: [String]
    public let branchContext: String?
    public let taskContext: [String]

    public init(
        query: String,
        purpose: String? = nil,
        scope: EventScope,
        privacyCeiling: PrivacyLevel,
        resultLimit: Int = 5,
        kinds: [MemoryKind] = [],
        recencyWindowDays: Int? = nil,
        fileContext: [String] = [],
        symbolContext: [String] = [],
        branchContext: String? = nil,
        taskContext: [String] = []
    ) {
        self.query = query
        self.purpose = purpose
        self.scope = scope
        self.privacyCeiling = privacyCeiling
        self.resultLimit = resultLimit
        self.kinds = kinds
        self.recencyWindowDays = recencyWindowDays
        self.fileContext = fileContext
        self.symbolContext = symbolContext
        self.branchContext = branchContext
        self.taskContext = taskContext
    }
}

public struct MemoryRecallHit: Codable, Equatable, Sendable {
    public let record: MemoryRecord
    public let score: Double
    public let provenance: MemoryProvenance

    public init(record: MemoryRecord, score: Double, provenance: MemoryProvenance) {
        self.record = record
        self.score = score
        self.provenance = provenance
    }
}

public struct MemoryProvenance: Codable, Equatable, Sendable {
    public let eventID: EventID
    public let correlationID: UUID
    public let checksum: String

    public init(eventID: EventID, correlationID: UUID, checksum: String) {
        self.eventID = eventID
        self.correlationID = correlationID
        self.checksum = checksum
    }
}

public struct MemoryRecallResponse: Codable, Equatable, Sendable {
    public let synthesizedContext: String
    public let records: [MemoryRecallHit]
    public let warnings: [String]

    public init(synthesizedContext: String, records: [MemoryRecallHit], warnings: [String]) {
        self.synthesizedContext = synthesizedContext
        self.records = records
        self.warnings = warnings
    }
}

public struct MemoryClassification: Equatable, Sendable {
    public let summary: String
    public let tags: [String]
    public let metadata: [String: String]
    public let warnings: [String]

    public init(summary: String, tags: [String], metadata: [String: String], warnings: [String]) {
        self.summary = summary
        self.tags = tags
        self.metadata = metadata
        self.warnings = warnings
    }
}

public protocol MemoryProjectionSink: Sendable {
    var sinkID: String { get }
    var schemaVersion: String { get }
    func accepts(_ record: MemoryRecord) -> Bool
    func write(record: MemoryRecord) async throws -> MemoryWriteReceipt
}

public protocol MemoryOperationalStore: Sendable {
    func upsert(_ record: MemoryRecord) async throws
    func fetchAll() async throws -> [MemoryRecord]
    func record(for memoryID: MemoryID) async throws -> MemoryRecord?
    func reset() async throws
}

public struct DefaultMemoryClassifier: Sendable {
    public init() {}

    public func classify(_ intent: RememberIntent) throws -> MemoryClassification {
        let trimmed = intent.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AndromedaRuntimeError.invalidMemoryContent("Memory content must not be empty.")
        }

        let tags = Array(
            Set(intent.tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
        ).sorted()
        let metadata = intent.metadata.reduce(into: [String: String]()) { partialResult, pair in
            let key = pair.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            partialResult[key] = pair.value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let summary = Self.makeSummary(from: trimmed)
        var warnings: [String] = []
        if trimmed.count > 2_000 {
            warnings.append("Memory content exceeded 2000 characters; summary was truncated.")
        }
        return MemoryClassification(summary: summary, tags: tags, metadata: metadata, warnings: warnings)
    }

    static func makeSummary(from content: String) -> String {
        let firstLine = content
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? content
        let collapsed = firstLine.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if collapsed.count <= 160 {
            return collapsed
        }
        return String(collapsed.prefix(157)) + "..."
    }
}

public struct DefaultMemoryRoutingPolicy: Sendable {
    public init() {}

    public func sinks(for record: MemoryRecord, availableSinks: [any MemoryProjectionSink]) -> [any MemoryProjectionSink] {
        availableSinks.filter { $0.accepts(record) }
    }
}
