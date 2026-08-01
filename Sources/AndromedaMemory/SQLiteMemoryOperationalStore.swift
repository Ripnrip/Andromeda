import AndromedaDomain
import CSQLite
import Foundation

public actor SQLiteMemoryOperationalStore: MemoryOperationalStore {
    private let databaseURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    nonisolated(unsafe) private var database: OpaquePointer?

    public init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        try Self.prepareStorage(at: databaseURL)
        self.database = try Self.openDatabase(at: databaseURL)
        try Self.execute(
            """
            CREATE TABLE IF NOT EXISTS memories (
                memory_id TEXT PRIMARY KEY,
                event_id TEXT NOT NULL,
                correlation_id TEXT NOT NULL,
                project_id TEXT,
                repository_id TEXT,
                session_id TEXT,
                user_id TEXT,
                team_id TEXT,
                organization_id TEXT,
                source_subsystem TEXT NOT NULL,
                source_actor TEXT NOT NULL,
                source_label TEXT NOT NULL,
                kind TEXT NOT NULL,
                privacy_level TEXT NOT NULL,
                summary TEXT NOT NULL,
                content TEXT NOT NULL,
                tags_json TEXT NOT NULL,
                metadata_json TEXT NOT NULL,
                related_json TEXT NOT NULL,
                checksum TEXT NOT NULL,
                created_at REAL NOT NULL
            );
            """,
            in: self.database
        )
        try Self.execute("CREATE INDEX IF NOT EXISTS memories_project_idx ON memories(project_id);", in: self.database)
        try Self.execute("CREATE INDEX IF NOT EXISTS memories_repository_idx ON memories(repository_id);", in: self.database)
        try Self.execute("CREATE INDEX IF NOT EXISTS memories_session_idx ON memories(session_id);", in: self.database)
        try Self.execute("CREATE INDEX IF NOT EXISTS memories_kind_idx ON memories(kind);", in: self.database)
        try Self.execute("CREATE INDEX IF NOT EXISTS memories_created_idx ON memories(created_at DESC);", in: self.database)
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    public func upsert(_ record: MemoryRecord) async throws {
        let statement = try prepare(
            """
            INSERT INTO memories (
                memory_id, event_id, correlation_id, project_id, repository_id, session_id, user_id, team_id,
                organization_id, source_subsystem, source_actor, source_label, kind, privacy_level, summary,
                content, tags_json, metadata_json, related_json, checksum, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(memory_id) DO UPDATE SET
                event_id = excluded.event_id,
                correlation_id = excluded.correlation_id,
                project_id = excluded.project_id,
                repository_id = excluded.repository_id,
                session_id = excluded.session_id,
                user_id = excluded.user_id,
                team_id = excluded.team_id,
                organization_id = excluded.organization_id,
                source_subsystem = excluded.source_subsystem,
                source_actor = excluded.source_actor,
                source_label = excluded.source_label,
                kind = excluded.kind,
                privacy_level = excluded.privacy_level,
                summary = excluded.summary,
                content = excluded.content,
                tags_json = excluded.tags_json,
                metadata_json = excluded.metadata_json,
                related_json = excluded.related_json,
                checksum = excluded.checksum,
                created_at = excluded.created_at;
            """
        )
        defer { sqlite3_finalize(statement) }

        try bind(record.memoryID.description, at: 1, in: statement)
        try bind(record.eventID.description, at: 2, in: statement)
        try bind(record.correlationID.uuidString.lowercased(), at: 3, in: statement)
        try bind(record.scope.projectID?.description, at: 4, in: statement)
        try bind(record.scope.repositoryID?.description, at: 5, in: statement)
        try bind(record.scope.sessionID?.description, at: 6, in: statement)
        try bind(record.scope.userID?.description, at: 7, in: statement)
        try bind(record.scope.teamID?.description, at: 8, in: statement)
        try bind(record.scope.organizationID?.description, at: 9, in: statement)
        try bind(record.source.subsystem, at: 10, in: statement)
        try bind(record.source.actor, at: 11, in: statement)
        try bind(record.source.label, at: 12, in: statement)
        try bind(record.kind.rawValue, at: 13, in: statement)
        try bind(record.privacyLevel.rawValue, at: 14, in: statement)
        try bind(record.summary, at: 15, in: statement)
        try bind(record.content, at: 16, in: statement)
        try bind(try encodeString(record.tags), at: 17, in: statement)
        try bind(try encodeString(record.metadata), at: 18, in: statement)
        try bind(try encodeString(record.relatedContext), at: 19, in: statement)
        try bind(record.checksum, at: 20, in: statement)
        try bind(record.createdAt.timeIntervalSince1970, at: 21, in: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw sqliteError("Failed to upsert memory record.")
        }
    }

    public func fetchAll() async throws -> [MemoryRecord] {
        let statement = try prepare(
            """
            SELECT
                memory_id, event_id, correlation_id, project_id, repository_id, session_id, user_id, team_id,
                organization_id, source_subsystem, source_actor, source_label, kind, privacy_level, summary,
                content, tags_json, metadata_json, related_json, checksum, created_at
            FROM memories
            ORDER BY created_at DESC;
            """
        )
        defer { sqlite3_finalize(statement) }

        var records: [MemoryRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            records.append(try decodeRecord(from: statement))
        }
        return records
    }

    public func record(for memoryID: MemoryID) async throws -> MemoryRecord? {
        let statement = try prepare(
            """
            SELECT
                memory_id, event_id, correlation_id, project_id, repository_id, session_id, user_id, team_id,
                organization_id, source_subsystem, source_actor, source_label, kind, privacy_level, summary,
                content, tags_json, metadata_json, related_json, checksum, created_at
            FROM memories
            WHERE memory_id = ?
            LIMIT 1;
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(memoryID.description, at: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return try decodeRecord(from: statement)
    }

    public func reset() async throws {
        try Self.execute("DELETE FROM memories;", in: database)
    }

    private func decodeRecord(from statement: OpaquePointer?) throws -> MemoryRecord {
        let memoryID = try typedID(MemoryID.self, from: columnText(0, in: statement))
        let eventID = try typedID(EventID.self, from: columnText(1, in: statement))
        guard let correlationID = UUID(uuidString: columnText(2, in: statement)) else {
            throw AndromedaRuntimeError.operationalStoreFailed("Invalid correlation UUID in SQLite row.")
        }

        let scope = EventScope(
            projectID: try optionalTypedID(ProjectID.self, from: columnOptionalText(3, in: statement)),
            memoryID: memoryID,
            repositoryID: try optionalTypedID(RepositoryID.self, from: columnOptionalText(4, in: statement)),
            sessionID: try optionalTypedID(SessionID.self, from: columnOptionalText(5, in: statement)),
            checkpointID: nil,
            leaseID: nil,
            environmentID: nil,
            userID: try optionalTypedID(UserID.self, from: columnOptionalText(6, in: statement)),
            teamID: try optionalTypedID(TeamID.self, from: columnOptionalText(7, in: statement)),
            organizationID: try optionalTypedID(OrganizationID.self, from: columnOptionalText(8, in: statement))
        )

        guard
            let kind = MemoryKind(rawValue: columnText(12, in: statement)),
            let privacyLevel = PrivacyLevel(rawValue: columnText(13, in: statement))
        else {
            throw AndromedaRuntimeError.operationalStoreFailed("Invalid kind or privacy level in SQLite row.")
        }

        return MemoryRecord(
            memoryID: memoryID,
            eventID: eventID,
            correlationID: correlationID,
            scope: scope,
            source: MemorySource(
                subsystem: columnText(9, in: statement),
                actor: columnText(10, in: statement),
                label: columnText(11, in: statement)
            ),
            kind: kind,
            privacyLevel: privacyLevel,
            summary: columnText(14, in: statement),
            content: columnText(15, in: statement),
            tags: try decode([String].self, from: columnText(16, in: statement)),
            metadata: try decode([String: String].self, from: columnText(17, in: statement)),
            relatedContext: try decode([String: [String]].self, from: columnText(18, in: statement)),
            checksum: columnText(19, in: statement),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 20))
        )
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        guard let database else {
            throw AndromedaRuntimeError.operationalStoreFailed("SQLite database is not open.")
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw sqliteError("Failed to prepare SQLite statement.")
        }
        return statement
    }

    private static func execute(_ sql: String, in database: OpaquePointer?) throws {
        guard let database else {
            throw AndromedaRuntimeError.operationalStoreFailed("SQLite database is not open.")
        }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw sqliteError("Failed to execute SQLite statement.", in: database)
        }
    }

    private func bind(_ value: String?, at index: Int32, in statement: OpaquePointer?) throws {
        if let value {
            guard sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
                throw sqliteError("Failed to bind SQLite text value.")
            }
        } else {
            guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
                throw sqliteError("Failed to bind SQLite null value.")
            }
        }
    }

    private func bind(_ value: Double, at index: Int32, in statement: OpaquePointer?) throws {
        guard sqlite3_bind_double(statement, index, value) == SQLITE_OK else {
            throw sqliteError("Failed to bind SQLite double value.")
        }
    }

    private func columnText(_ index: Int32, in statement: OpaquePointer?) -> String {
        String(cString: sqlite3_column_text(statement, index))
    }

    private func columnOptionalText(_ index: Int32, in statement: OpaquePointer?) -> String? {
        guard let value = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: value)
    }

    private func encodeString<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw AndromedaRuntimeError.operationalStoreFailed("Failed to encode SQLite JSON value.")
        }
        return string
    }

    private func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        try decoder.decode(type, from: Data(string.utf8))
    }

    private func typedID<T: TypedIdentifier>(_ type: T.Type, from string: String) throws -> T {
        guard let uuid = UUID(uuidString: string) else {
            throw AndromedaRuntimeError.operationalStoreFailed("Invalid UUID string \(string) in SQLite row.")
        }
        guard let identifier = T(rawValue: uuid) else {
            throw AndromedaRuntimeError.operationalStoreFailed(
                "Could not initialize typed identifier \(T.self) from UUID \(string)."
            )
        }
        return identifier
    }

    private func optionalTypedID<T: TypedIdentifier>(_ type: T.Type, from string: String?) throws -> T? {
        guard let string else { return nil }
        return try typedID(type, from: string)
    }

    private func sqliteError(_ message: String) -> AndromedaRuntimeError {
        Self.sqliteError(message, in: database)
    }

    private static func sqliteError(_ message: String, in database: OpaquePointer?) -> AndromedaRuntimeError {
        let detail: String
        if let database, let raw = sqlite3_errmsg(database) {
            detail = String(cString: raw)
        } else {
            detail = "Unknown SQLite error."
        }
        return .operationalStoreFailed("\(message) \(detail)")
    }

    private static func prepareStorage(at databaseURL: URL) throws {
        let directoryURL = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: databaseURL.path) {
            _ = FileManager.default.createFile(atPath: databaseURL.path, contents: nil)
        }
    }

    private static func openDatabase(at databaseURL: URL) throws -> OpaquePointer? {
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else {
            if let database {
                let message = String(cString: sqlite3_errmsg(database))
                sqlite3_close(database)
                throw AndromedaRuntimeError.operationalStoreFailed("Failed to open SQLite database. \(message)")
            }
            throw AndromedaRuntimeError.operationalStoreFailed("Failed to open SQLite database.")
        }
        return database
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
