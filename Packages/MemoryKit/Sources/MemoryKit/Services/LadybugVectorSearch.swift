/**
 * 🐞 The LadybugVectorSearch - The Warm Probe of the Archival Index
 *
 * "The Librarian need not own the constellation to read it — a whispered
 * needle across the wire to the ever-open reading room on :8286, and the
 * kindred thoughts drift back with their distances held high."
 *
 * - The Enchanted Recall Observatory of Anima
 *
 * Contract: docs/DATA-CONTRACTS.md §10 (vector_search) + §13 (thin payload).
 * The index is a derived, rebuildable cache — a down server DEGRADES recall,
 * it never fails it (fail-open, same discipline as the vault ripgrep stage).
 */

import Foundation

// MARK: - Hits & Outcome

/// 🐞 LadybugSearchHit — one thin-metadata neighbour from the index server.
///
/// `/query` returns a bare JSON array with a uniform base shape
/// (`id`, `path`, `project`, `agent`, `title`, `distance`) plus a `table`
/// discriminator; §13 cache hits additionally carry their thin payload
/// (`point_id`, `content_hash`, `visibility`, `date`, `tags`, `source_path`).
/// Every field is optional-tolerant: the server evolves, recall must not topple.
public struct LadybugSearchHit: Sendable, Equatable {
    public let pointID: String?
    public let contentHash: String?
    public let visibility: String?
    public let project: String?
    public let path: String?
    public let title: String?
    public let date: String?
    public let tags: [String]
    public let table: String?
    /// Cosine distance from the query vector (0 = identical direction).
    public let distance: Double

    /// 🌟 Crystallize one neighbour from the reading room's reply.
    public init(
        pointID: String? = nil,
        contentHash: String? = nil,
        visibility: String? = nil,
        project: String? = nil,
        path: String? = nil,
        title: String? = nil,
        date: String? = nil,
        tags: [String] = [],
        table: String? = nil,
        distance: Double
    ) {
        self.pointID = pointID
        self.contentHash = contentHash
        self.visibility = visibility
        self.project = project
        self.path = path
        self.title = title
        self.date = date
        self.tags = tags
        self.table = table
        self.distance = distance
    }
}

/// 🌊 LadybugSearchOutcome — hits plus fail-open degradation flags (vault-stage shape).
public struct LadybugSearchOutcome: Sendable, Equatable {
    public let hits: [LadybugSearchHit]
    public let degraded: Bool
    public let reason: String?

    /// 🌟 Assemble the outcome of one probe.
    public init(hits: [LadybugSearchHit], degraded: Bool, reason: String? = nil) {
        self.hits = hits
        self.degraded = degraded
        self.reason = reason
    }
}

// MARK: - Injectable Probe

/// 🐞 LadybugVectorSearching — mockable face of the index server (never bake URLSession into tests).
public protocol LadybugVectorSearching: Sendable {
    /// 🔎 Probe `GET /query?q=<text>&k=<k>` — never throws; failures degrade.
    func search(text: String, k: Int) async -> LadybugSearchOutcome
}

// MARK: - Real Client

/// 🐞 LadybugVectorSearch — URLSession probe of the persistent index server.
///
/// Fail-open by contract (§13 constraint 2): connection refusal, timeout,
/// non-2xx status, or a malformed payload all yield `degraded` with a reason
/// and zero hits — the caller's recall pipeline continues untouched.
public struct LadybugVectorSearch: LadybugVectorSearching {
    private let baseURL: URL
    private let session: URLSession

    /// 🌐 Bind the probe to an index server (default Ladybug `:8286`).
    public init(baseURL: URL = URL(string: "http://127.0.0.1:8286")!) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2.0
        config.timeoutIntervalForResource = 4.0
        self.session = URLSession(configuration: config)
    }

    /// 🔎 One warm probe — encode the needle, decode the neighbours, degrade on storms.
    public func search(text: String, k: Int) async -> LadybugSearchOutcome {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("query"),
                                              resolvingAgainstBaseURL: false) else {
            return LadybugSearchOutcome(hits: [], degraded: true,
                                        reason: "ladybug base URL unparseable")
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "k", value: String(max(1, k)))
        ]
        guard let url = components.url else {
            return LadybugSearchOutcome(hits: [], degraded: true,
                                        reason: "ladybug query URL unparseable")
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                return LadybugSearchOutcome(hits: [], degraded: true,
                                            reason: "ladybug response not HTTP")
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                return LadybugSearchOutcome(hits: [], degraded: true,
                                            reason: "ladybug HTTP \(httpResponse.statusCode)")
            }
            // Malformed 2xx bodies must surface as degradation, not as a
            // silent empty index — a broken/incompatible server stays
            // observable (review r4213544639). A valid empty array is healthy.
            guard let hits = Self.parseHits(data) else {
                return LadybugSearchOutcome(hits: [], degraded: true,
                                            reason: "ladybug malformed /query payload")
            }
            return LadybugSearchOutcome(hits: hits, degraded: false)
        } catch {
            return LadybugSearchOutcome(hits: [], degraded: true,
                                        reason: "ladybug unreachable: \(error.localizedDescription)")
        }
    }

    /// 🧾 Parse the bare-array `/query` payload — tolerate missing keys per hit.
    /// Returns nil when the body is not a JSON array of objects at all — the
    /// caller treats that as a degraded backend, never as "no hits".
    static func parseHits(_ data: Data) -> [LadybugSearchHit]? {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        return rows.compactMap { row in
            // `distance` is the only load-bearing field — a row without it is noise.
            guard let distance = row["distance"] as? Double else { return nil }
            return LadybugSearchHit(
                pointID: row["point_id"] as? String,
                contentHash: row["content_hash"] as? String,
                visibility: row["visibility"] as? String,
                project: row["project"] as? String,
                path: (row["source_path"] as? String) ?? (row["path"] as? String),
                title: row["title"] as? String,
                date: row["date"] as? String,
                tags: (row["tags"] as? [String]) ?? [],
                table: row["table"] as? String,
                distance: distance
            )
        }
    }
}
