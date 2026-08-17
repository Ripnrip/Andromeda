import Foundation

// MARK: - State store errors

public enum WitnessStoreError: Error, Equatable, LocalizedError {
    case decodeFailed(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .decodeFailed(reason):
            return "Witness state decode failed: \(reason)"
        case let .writeFailed(reason):
            return "Witness state write failed: \(reason)"
        }
    }
}

// MARK: - State store protocol

/// Injectable persistence boundary for per-target state and transition logs.
public protocol WitnessStoring: Sendable {
    /// Load state for a target. Returns fresh initial state when the file is
    /// missing. Throws on corrupt JSON so the engine can surface the failure
    /// rather than silently resetting.
    func loadState(targetLabel: String, path: String) async throws -> WitnessTargetState

    /// Atomically persist state for a target.
    func saveState(_ state: WitnessTargetState, path: String) async throws

    /// Append a transition event to the JSONL log.
    func appendTransition(_ event: WitnessTransitionEvent, path: String) async throws

    /// Read recent transition events from the JSONL log (newest last),
    /// capped at `limit`.
    func readTransitions(path: String, limit: Int) async throws -> [WitnessTransitionEvent]
}

// MARK: - Filesystem-backed store

/// Production store using atomic JSON writes for state and append-only JSONL
/// for transition logs. Failures surface as `WitnessStoreError` — never
/// silently disappear.
public struct WitnessFileStore: WitnessStoring {
    private let dateProvider: @Sendable () -> Date

    public init(
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.dateProvider = dateProvider
    }

    public func loadState(targetLabel: String, path: String) async throws -> WitnessTargetState {
        guard FileManager.default.fileExists(atPath: path) else {
            return .initial(targetLabel: targetLabel)
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let state = try decoder.decode(WitnessTargetState.self, from: data)
            // Validate the label matches — corrupt or wrong-target state must surface.
            guard state.targetLabel == targetLabel else {
                throw WitnessStoreError.decodeFailed(
                    "label mismatch: expected '\(targetLabel)', found '\(state.targetLabel)'"
                )
            }
            return state
        } catch let error as WitnessStoreError {
            throw error
        } catch {
            throw WitnessStoreError.decodeFailed(error.localizedDescription)
        }
    }

    public func saveState(_ state: WitnessTargetState, path: String) async throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(state)
            // Atomic write prevents partial reads on crash.
            try data.write(
                to: URL(fileURLWithPath: path),
                options: [.atomic]
            )
        } catch {
            throw WitnessStoreError.writeFailed(error.localizedDescription)
        }
    }

    public func appendTransition(_ event: WitnessTransitionEvent, path: String) async throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        do {
            let data = try encoder.encode(event)
            guard let line = String(data: data, encoding: .utf8) else {
                throw WitnessStoreError.writeFailed("failed to encode transition event as UTF-8")
            }
            if FileManager.default.fileExists(atPath: path) {
                // Append-only — an error opening an existing journal must
                // surface; never fall back to replacing its history.
                let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data((line + "\n").utf8))
            } else {
                try (line + "\n").write(
                    toFile: path,
                    atomically: true,
                    encoding: .utf8
                )
            }
        } catch {
            throw WitnessStoreError.writeFailed(error.localizedDescription)
        }
    }

    public func readTransitions(path: String, limit: Int) async throws -> [WitnessTransitionEvent] {
        guard FileManager.default.fileExists(atPath: path) else {
            return []
        }
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw WitnessStoreError.decodeFailed(error.localizedDescription)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var events: [WitnessTransitionEvent] = []
        var seenIDs: Set<UUID> = []
        for line in String(data: data, encoding: .utf8)?.split(separator: "\n") ?? [] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            do {
                let lineData = Data(trimmed.utf8)
                let event = try decoder.decode(WitnessTransitionEvent.self, from: lineData)
                if seenIDs.insert(event.id).inserted {
                    events.append(event)
                }
            } catch {
                throw WitnessStoreError.decodeFailed("corrupt JSONL line: \(error.localizedDescription)")
            }
        }
        // Return last `limit` entries (newest last).
        guard events.count > limit else { return events }
        return Array(events.suffix(limit))
    }
}

// MARK: - In-memory store (for tests)

/// In-memory store for tests — keeps state and logs in dictionaries without
/// touching the filesystem.
public actor InMemoryWitnessStore: WitnessStoring {
    private var states: [String: WitnessTargetState] = [:]
    private var transitions: [String: [WitnessTransitionEvent]] = [:]

    public init() {}

    public func loadState(targetLabel: String, path: String) async throws -> WitnessTargetState {
        if let state = states[path] {
            guard state.targetLabel == targetLabel else {
                throw WitnessStoreError.decodeFailed(
                    "label mismatch: expected '\(targetLabel)', found '\(state.targetLabel)'"
                )
            }
            return state
        }
        return .initial(targetLabel: targetLabel)
    }

    public func saveState(_ state: WitnessTargetState, path: String) async throws {
        states[path] = state
    }

    public func appendTransition(_ event: WitnessTransitionEvent, path: String) async throws {
        transitions[path, default: []].append(event)
    }

    public func readTransitions(path: String, limit: Int) async throws -> [WitnessTransitionEvent] {
        let all = transitions[path] ?? []
        guard all.count > limit else { return all }
        return Array(all.suffix(limit))
    }

    /// Direct accessor for test assertions.
    public func recordedTransitions(forPath path: String) -> [WitnessTransitionEvent] {
        transitions[path] ?? []
    }
}
