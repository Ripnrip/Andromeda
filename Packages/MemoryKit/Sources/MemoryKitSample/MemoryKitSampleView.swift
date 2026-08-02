import SwiftUI
import MemoryKit

/// Minimal dogfood shell for the hot spine: `memory.store` + `memory.recall`.
@MainActor
@Observable
final class MemoryKitSampleModel {
    var storeText = ""
    var recallText = ""
    var hits: [MemoryHit] = []
    var statusMessage = "Ready — in-memory hot store."
    var lastStoredID: UUID?
    var latestSealPreview: String?

    private let capture: CaptureService
    private let retrieval: RetrievalService

    init(capture: CaptureService, retrieval: RetrievalService) {
        self.capture = capture
        self.retrieval = retrieval
    }

    static func bootstrap() throws -> MemoryKitSampleModel {
        let container = try SwiftDataContainer.createInMemory()
        let capture = CaptureService(container: container, ledger: AnimaLedger())
        let retrieval = RetrievalService(container: container, vaultURL: nil)
        return MemoryKitSampleModel(capture: capture, retrieval: retrieval)
    }

    func store() async {
        let text = storeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            statusMessage = "Store text is empty."
            return
        }
        do {
            let id = try await capture.storeMemory(
                narrative: text,
                project: "MemoryKitSample",
                agent: "MemoryKitSampleApp",
                provenance: "sample-app"
            )
            lastStoredID = id
            latestSealPreview = await capture.latestSeal.map { String($0.prefix(24)) + "…" }
            statusMessage = "Stored \(id.uuidString.prefix(8))…"
            storeText = ""
        } catch {
            statusMessage = "Store failed: \(error.localizedDescription)"
        }
    }

    func recall() async {
        let text = recallText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let result = try await retrieval.recallMemory(
                RecallQuery(text: text.isEmpty ? nil : text, limit: 10, includeVaultFallback: false)
            )
            hits = result.hits
            statusMessage = "Recall: \(result.hotHitCount) hot hits (vault skipped in sample)."
        } catch {
            statusMessage = "Recall failed: \(error.localizedDescription)"
            hits = []
        }
    }
}

struct MemoryKitSampleView: View {
    @State private var model: MemoryKitSampleModel?

    var body: some View {
        Group {
            if let model {
                content(model: model)
            } else {
                ProgressView("Bootstrapping in-memory hot store…")
            }
        }
        .padding(20)
        .task {
            if model == nil {
                model = try? MemoryKitSampleModel.bootstrap()
            }
        }
    }

    @ViewBuilder
    private func content(model: MemoryKitSampleModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            storeSection(model: model)
            recallSection(model: model)
            statusSection(model: model)
            hitsSection(model: model)
            Spacer(minLength: 0)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MemoryKit Sample")
                .font(.title2.bold())
            Text("Hot episodic spine — CaptureService + RetrievalService (no vault / indexes).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func storeSection(model: MemoryKitSampleModel) -> some View {
        GroupBox("memory.store") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Narrative to capture…", text: Bindable(model).storeText, axis: .vertical)
                    .lineLimit(3...6)
                Button("Store") {
                    Task { await model.store() }
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private func recallSection(model: MemoryKitSampleModel) -> some View {
        GroupBox("memory.recall") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Query (optional — empty lists recent hot)", text: Bindable(model).recallText)
                Button("Recall") {
                    Task { await model.recall() }
                }
            }
        }
    }

    private func statusSection(model: MemoryKitSampleModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let seal = model.latestSealPreview {
                Text("Latest seal: \(seal)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func hitsSection(model: MemoryKitSampleModel) -> some View {
        GroupBox("Hits (\(model.hits.count))") {
            if model.hits.isEmpty {
                Text("No hits yet.")
                    .foregroundStyle(.secondary)
            } else {
                List(model.hits) { hit in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hit.narrative)
                            .lineLimit(2)
                        Text("\(hit.source.rawValue) · score \(hit.score, format: .number.precision(.fractionLength(2)))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxHeight: 160)
            }
        }
    }
}

#Preview {
    MemoryKitSampleView()
}
