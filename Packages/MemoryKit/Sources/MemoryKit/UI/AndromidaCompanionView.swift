/**
 * AndromidaCompanionView — operator surface for the complexity curtain (BIN-252).
 *
 * Exposes retain / recall / health / outbox queue insights. JSON is authority;
 * live projection is fail-open. Backend brands never appear in chrome.
 */

import Foundation
import Observation
import SwiftUI

/// Presentation model for the Andromida companion.
@MainActor
@Observable
public final class AndromidaCompanionModel {
    public private(set) var insights: CompanionOutboxInsights?
    public private(set) var health: CurtainHealthReport?
    public private(set) var lastRecall: RecallResponse?
    public private(set) var lastRetainID: String?
    public private(set) var statusMessage: String = "Ready"
    public var recallQuery: String = ""
    public var retainNarrative: String = ""

    private let curtain: MemoryComplexityCurtain

    public init(curtain: MemoryComplexityCurtain) {
        self.curtain = curtain
    }

    /// Refresh health + queue insights.
    public func refresh() async {
        health = await curtain.health()
        insights = await curtain.outboxQueueInsights()
        statusMessage = "Health \(health?.level.rawValue ?? "unknown")"
    }

    /// Operator retain via curtain.
    public func retain() async {
        let narrative = retainNarrative.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !narrative.isEmpty else {
            statusMessage = "Retain needs a narrative."
            return
        }
        do {
            let receipt = try await curtain.retain(
                narrative: narrative,
                project: "companion",
                agent: "andromida-companion"
            )
            lastRetainID = receipt.memoryID.uuidString
            retainNarrative = ""
            statusMessage = "Retained \(receipt.memoryID.uuidString.prefix(8))…"
            await refresh()
        } catch {
            statusMessage = "Retain failed: \(error.localizedDescription)"
        }
    }

    /// Operator recall via curtain.
    public func recall() async {
        let query = recallQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            statusMessage = "Recall needs a query."
            return
        }
        lastRecall = await curtain.recall(query: query)
        statusMessage = "Recall \(lastRecall?.hits.count ?? 0) hit(s) · intent \(lastRecall?.intent.rawValue ?? "?")"
    }

    /// Rebuild live projection from JSON authority.
    public func rebuildProjection() async {
        await curtain.rebuildProjectionFromAuthority()
        statusMessage = "Projection rebuilt from JSON authority."
        await refresh()
    }
}

/// SwiftUI companion panel — queue + verbs, no store brands.
public struct AndromidaCompanionView: View {
    @Bindable private var model: AndromidaCompanionModel

    public init(model: AndromidaCompanionModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            queueStrip
            retainRow
            recallRow
            recallHits
            actions
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 480)
        .task {
            await model.refresh()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Andromida")
                .font(.title2.weight(.semibold))
            Text(model.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
            if let health = model.health {
                Text(healthLine(health))
                    .font(.caption)
                    .foregroundStyle(health.drift.drifted ? .orange : .secondary)
            }
        }
    }

    private var queueStrip: some View {
        HStack(spacing: 12) {
            queueBadge(title: "Pending", value: model.insights?.pending ?? 0)
            queueBadge(title: "Delivered", value: model.insights?.delivered ?? 0)
            queueBadge(title: "Dead letter", value: model.insights?.deadLetter ?? 0)
        }
    }

    private func queueBadge(title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title3.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var retainRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Retain")
                .font(.headline)
            TextField("Durable narrative…", text: $model.retainNarrative, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
            Button("memory_retain") {
                Task { await model.retain() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var recallRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recall")
                .font(.headline)
            TextField("Query…", text: $model.recallQuery)
                .textFieldStyle(.roundedBorder)
            Button("memory_recall") {
                Task { await model.recall() }
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var recallHits: some View {
        if let hits = model.lastRecall?.hits, !hits.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Hits")
                    .font(.headline)
                ForEach(hits.prefix(5)) { hit in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hit.title)
                            .font(.subheadline.weight(.medium))
                        Text(hit.body)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var actions: some View {
        HStack {
            Button("memory_health") {
                Task { await model.refresh() }
            }
            Button("Rebuild projection") {
                Task { await model.rebuildProjection() }
            }
        }
    }

    private func healthLine(_ health: CurtainHealthReport) -> String {
        var parts = ["Level \(health.level.rawValue)"]
        if health.drift.drifted {
            parts.append("drift missing=\(health.drift.missingInProjection) extra=\(health.drift.extraInProjection)")
        }
        if let failure = health.projectionFailure {
            parts.append(failure)
        }
        return parts.joined(separator: " · ")
    }
}
