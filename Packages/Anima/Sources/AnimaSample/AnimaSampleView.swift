import SwiftUI
import ComposableArchitecture
import MemoryKit
import AnimaCore
import AnimaKnowledge
import AnimaIndexing

struct AnimaSampleView: View {
    @State private var store = Store(initialState: MemoryReducer.State()) {
        MemoryReducer()
    }
    @State private var materializerStatus = "Idle"
    @State private var indexerStatus = "Not probed"
    @State private var backend: AnimaSampleBackend?

    var body: some View {
        TabView {
            reducerTab
                .tabItem { Label("TCA Core", systemImage: "brain") }
            materializerTab
                .tabItem { Label("Knowledge", systemImage: "doc.text") }
            indexerTab
                .tabItem { Label("Indexing", systemImage: "point.3.connected.trianglepath.dotted") }
        }
        .padding(12)
        .task {
            if backend == nil {
                backend = try? await AnimaSampleBackend.bootstrap()
            }
        }
    }

    private var reducerTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AnimaCore — MemoryReducer")
                .font(.title3.bold())
            Text("Sync / health / visibility orchestration (TCA).")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Sync") { store.send(.triggerSync) }
                Button("Probe health") { store.send(.checkConnectionHealth) }
                Button("Visibility → friends") { store.send(.changeVisibility(.friends)) }
            }
            LabeledContent("Sync", value: label(for: store.syncStatus))
            LabeledContent("Visibility", value: store.activeVisibility.rawValue)
            LabeledContent("Captures", value: "\(store.recentCaptures.count)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var materializerTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AnimaKnowledge — ObsidianMaterializer")
                .font(.title3.bold())
            Text("Projects hot captures into a temp vault under /tmp.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Seed hot + materialize pending") {
                Task { await runMaterializer() }
            }
            .disabled(backend == nil)
            Text(materializerStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var indexerTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AnimaIndexing — Ladybug / Qdrant clients")
                .font(.title3.bold())
            Text("Fail-open HTTP adapters (Studio :8286 / Qdrant :6333).")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Probe Ladybug health") {
                Task { await probeLadybug() }
            }
            Text(indexerStatus)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func label(for status: SyncStatus) -> String {
        switch status {
        case .idle: return "idle"
        case .syncing: return "syncing"
        case .success: return "success"
        case .failed: return "failed"
        }
    }

    private func runMaterializer() async {
        guard let backend else { return }
        materializerStatus = "Running…"
        do {
            let report = try await backend.materializeDemo()
            materializerStatus = "written=\(report.writtenCount) merged=\(report.mergedCount) failed=\(report.failedCount)"
        } catch {
            materializerStatus = "Error: \(error.localizedDescription)"
        }
    }

    private func probeLadybug() async {
        indexerStatus = "Probing :8286…"
        guard let url = URL(string: "http://127.0.0.1:8286/health") else { return }
        do {
            let (_, resp) = try await URLSession.shared.data(from: url)
            if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                indexerStatus = "Ladybug :8286 OK (HTTP \(http.statusCode))"
            } else {
                indexerStatus = "Ladybug unhealthy"
            }
        } catch {
            indexerStatus = "Ladybug unreachable: \(error.localizedDescription)"
        }
    }
}

/// Shared hot store + temp vault for the materializer demo.
actor AnimaSampleBackend {
    let container: SwiftDataContainer
    let capture: CaptureService
    let vaultRoot: URL
    let materializer: ObsidianMaterializer

    static func bootstrap() async throws -> AnimaSampleBackend {
        let container = try SwiftDataContainer.createInMemory()
        let capture = CaptureService(container: container, ledger: nil)
        let vaultRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnimaSample-vault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultRoot, withIntermediateDirectories: true)
        let materializer = ObsidianMaterializer(store: container, vaultRoot: vaultRoot)
        return AnimaSampleBackend(container: container, capture: capture, vaultRoot: vaultRoot, materializer: materializer)
    }

    init(container: SwiftDataContainer, capture: CaptureService, vaultRoot: URL, materializer: ObsidianMaterializer) {
        self.container = container
        self.capture = capture
        self.vaultRoot = vaultRoot
        self.materializer = materializer
    }

    func materializeDemo() async throws -> MaterializationBatchReport {
        _ = try await capture.storeMemory(
            narrative: "AnimaSample materializer demo \(Date())",
            project: "AnimaSample",
            agent: "AnimaSampleApp",
            provenance: "sample-app"
        )
        return await materializer.materializePending()
    }
}

#Preview {
    AnimaSampleView()
}
