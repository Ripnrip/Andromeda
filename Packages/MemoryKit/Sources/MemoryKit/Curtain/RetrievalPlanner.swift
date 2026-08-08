/**
 * RetrievalPlanner + RankFusion — intent routing and fused recall (BIN-250).
 *
 * Agents never pick backends. The planner classifies query intent, routes to
 * available recall sources, merges via reciprocal rank fusion, then suppresses
 * tombstoned IDs.
 */

import Foundation

/// Query intents the curtain understands.
public enum RecallQueryIntent: String, Sendable, Codable, CaseIterable, Equatable {
    case exact
    case temporal
    case longDocument
    case codeGraph
    case synthesis
    case auto
}

/// Opaque backend route IDs — operator/curtain only, never client menus.
public enum RecallBackendRoute: String, Sendable, Codable, CaseIterable, Equatable {
    case hotWorking
    case durableOutbox
    case longDocumentIndex
    case codeGraph
    case synthesis
}

/// One planned backend probe.
public struct RecallPlanStep: Sendable, Equatable {
    public let route: RecallBackendRoute
    public let reason: String

    public init(route: RecallBackendRoute, reason: String) {
        self.route = route
        self.reason = reason
    }
}

public struct RecallPlan: Sendable, Equatable {
    public let intent: RecallQueryIntent
    public let steps: [RecallPlanStep]

    public init(intent: RecallQueryIntent, steps: [RecallPlanStep]) {
        self.intent = intent
        self.steps = steps
    }
}

/// A hit produced by one backend before fusion.
public struct RawRecallHit: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let title: String
    public let body: String
    public let route: RecallBackendRoute
    public let score: Double
    public let createdAt: Date

    public init(
        id: UUID,
        title: String,
        body: String,
        route: RecallBackendRoute,
        score: Double,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.route = route
        self.score = score
        self.createdAt = createdAt
    }
}

/// Fused recall hit returned to callers (no backend brands).
public struct FusedRecallHit: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let title: String
    public let body: String
    public let fusedScore: Double
    public let contributingRoutes: [RecallBackendRoute]

    public init(
        id: UUID,
        title: String,
        body: String,
        fusedScore: Double,
        contributingRoutes: [RecallBackendRoute]
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.fusedScore = fusedScore
        self.contributingRoutes = contributingRoutes
    }
}

public struct RecallPlanner: Sendable {
    public init() {}

    /// Classify intent from query text + optional caller hint.
    public func classify(query: String, hint: RecallQueryIntent = .auto) -> RecallQueryIntent {
        if hint != .auto { return hint }
        let lower = query.lowercased()

        if lower.contains("when ") || lower.contains("yesterday") || lower.contains("last week")
            || lower.contains("on 20") || lower.range(of: #"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\b"#, options: .regularExpression) != nil
        {
            return .temporal
        }
        if lower.contains("chapter") || lower.contains("section") || lower.contains("document")
            || lower.contains("long form") || lower.contains("essay")
        {
            return .longDocument
        }
        if lower.contains("symbol") || lower.contains("function") || lower.contains("class ")
            || lower.contains("call graph") || lower.contains("depends on") || lower.contains("imports ")
        {
            return .codeGraph
        }
        if lower.contains("summarize") || lower.contains("synthesis") || lower.contains("overall")
            || lower.contains("what do we know")
        {
            return .synthesis
        }
        if lower.contains("exact") || lower.hasPrefix("id:") || lower.contains("content_hash") {
            return .exact
        }
        return .exact
    }

    /// Build a route plan for the classified intent.
    public func plan(for intent: RecallQueryIntent) -> RecallPlan {
        switch intent {
        case .exact:
            return RecallPlan(intent: intent, steps: [
                RecallPlanStep(route: .durableOutbox, reason: "exact match over durable authority"),
                RecallPlanStep(route: .hotWorking, reason: "recent working set"),
            ])
        case .temporal:
            return RecallPlan(intent: intent, steps: [
                RecallPlanStep(route: .hotWorking, reason: "recent episodic window"),
                RecallPlanStep(route: .durableOutbox, reason: "durable timeline"),
            ])
        case .longDocument:
            return RecallPlan(intent: intent, steps: [
                RecallPlanStep(route: .longDocumentIndex, reason: "structure-aware long doc"),
                RecallPlanStep(route: .durableOutbox, reason: "fallback durable narrative"),
            ])
        case .codeGraph:
            return RecallPlan(intent: intent, steps: [
                RecallPlanStep(route: .codeGraph, reason: "relation / symbol graph"),
                RecallPlanStep(route: .hotWorking, reason: "recent code notes"),
            ])
        case .synthesis:
            return RecallPlan(intent: intent, steps: [
                RecallPlanStep(route: .synthesis, reason: "multi-source synthesis"),
                RecallPlanStep(route: .durableOutbox, reason: "durable facts"),
                RecallPlanStep(route: .hotWorking, reason: "working context"),
            ])
        case .auto:
            return plan(for: .exact)
        }
    }
}

/// Reciprocal Rank Fusion over multi-backend hit lists.
public enum RankFusion: Sendable {
    /// Classic RRF with constant `k` (default 60).
    public static func fuse(
        lists: [[RawRecallHit]],
        k: Double = 60,
        tombstones: Set<UUID> = [],
        limit: Int = 20
    ) -> [FusedRecallHit] {
        struct Acc {
            var title: String
            var body: String
            var score: Double
            var routes: Set<RecallBackendRoute>
        }

        var merged: [UUID: Acc] = [:]
        for list in lists {
            let ranked = list.sorted { $0.score > $1.score }
            for (index, hit) in ranked.enumerated() {
                if tombstones.contains(hit.id) { continue }
                let contribution = 1.0 / (k + Double(index + 1))
                if var existing = merged[hit.id] {
                    existing.score += contribution
                    existing.routes.insert(hit.route)
                    // Prefer longer body when merging.
                    if hit.body.count > existing.body.count {
                        existing.body = hit.body
                        existing.title = hit.title
                    }
                    merged[hit.id] = existing
                } else {
                    merged[hit.id] = Acc(
                        title: hit.title,
                        body: hit.body,
                        score: contribution,
                        routes: [hit.route]
                    )
                }
            }
        }

        return merged
            .map { id, acc in
                FusedRecallHit(
                    id: id,
                    title: acc.title,
                    body: acc.body,
                    fusedScore: acc.score,
                    contributingRoutes: acc.routes.sorted { $0.rawValue < $1.rawValue }
                )
            }
            .sorted {
                if $0.fusedScore == $1.fusedScore {
                    return $0.title < $1.title
                }
                return $0.fusedScore > $1.fusedScore
            }
            .prefix(limit)
            .map { $0 }
    }
}

/// Lexical scorer used by default backend adapters.
public enum CurtainLexicalScorer: Sendable {
    public static func score(query: String, haystack: String) -> Double {
        let terms = query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return 0 }
        let lower = haystack.lowercased()
        let matches = terms.reduce(into: 0) { count, term in
            if lower.contains(term) { count += 1 }
        }
        guard matches > 0 else { return 0 }
        return Double(matches) * 10.0
    }
}
