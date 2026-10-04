import AndromedaAppControl
import AndromedaHUDCore
import Foundation
import MemoryKit
import Testing

/// 🧪 ≡ proof for the HUD App Control bridges (HAB-838): the dispatcher
/// drives the *same* HUDModel methods the on-glass controls call, the
/// snapshot is curated (never a dump), and the contract round-trips Codable.
///
/// Hermetic posture: `memorySessionReady: false` keeps MemoryKit off disk so
/// submit paths deterministically land in `.failed` on both sides of the ≡.
@Suite("AndromedaAppControl.HUDModelBridges")
@MainActor
struct HUDModelAppControlTests {
    private func makeModel(recentQueries: [String] = []) -> HUDModel {
        HUDModel(
            projectSurface: InMemoryProjectStateStore(),
            memorySessionReady: false,
            recentQueries: recentQueries
        )
    }

    // MARK: - Dispatch ≡ click path

    @Test("dispatch(submit) ≡ Enter path: same outcome, recents, and field mirror")
    func submitEquivalence() async throws {
        let viaDispatcher = makeModel(recentQueries: [])
        let viaKeyboard = makeModel(recentQueries: [])

        let outcome = await HUDModelAppControlDispatcher(model: viaDispatcher)
            .dispatch(.submitQuery(query: "store bridge check"))
        await viaKeyboard.submitQuery("store bridge check")

        // Both not-ready sessions produce the same failure — deterministic
        // on both sides of the equivalence.
        #expect(outcome.status == .ok)
        if case .failed(let dispatchedMessage) = viaDispatcher.lastOutcome,
           case .failed(let typedMessage) = viaKeyboard.lastOutcome {
            #expect(dispatchedMessage == typedMessage)
        } else {
            Issue.record("expected .failed on both paths, got \(viaDispatcher.lastOutcome) vs \(viaKeyboard.lastOutcome)")
        }
        #expect(viaDispatcher.recentQueries == viaKeyboard.recentQueries)
        // The dispatcher mirrors the field exactly as typing would.
        #expect(viaDispatcher.fieldQuery == "store bridge check")
    }

    @Test("dispatch(dismiss) ≡ Escape path: in-flight cancelled, results cleared")
    func dismissEquivalence() async {
        let model = makeModel()
        model.lastOutcome = .failed(message: "stale outcome")
        await model.submitQuery("recall anything") // not-ready → failed, panel shown

        let outcome = await HUDModelAppControlDispatcher(model: model)
            .dispatch(.dismissResults)

        #expect(outcome.status == .ok)
        #expect(model.lastOutcome == .idle)
        #expect(model.lastOutcome.showsResultsPanel == false)
    }

    @Test("dispatch(focus) posts the exact status-item notification")
    func focusEquivalence() async throws {
        let model = makeModel()
        let flag = NotificationFlag(name: .andromedaHUDFocusSearch)

        let outcome = await HUDModelAppControlDispatcher(model: model)
            .dispatch(.focusSearch)

        #expect(outcome.status == .ok)
        // Selector-based observers deliver synchronously — no runloop dance.
        #expect(flag.fired)
        flag.remove()
    }

    @Test("dispatch(refresh-fleet-pulse) repopulates the chip pulse")
    func refreshFleetPulse() async {
        let model = makeModel()
        model.fleetPulse = HUDFleetPulse(status: .unknown, attentionCount: 0, detail: "stale")

        let outcome = await HUDModelAppControlDispatcher(model: model)
            .dispatch(.refreshFleetPulse)

        #expect(outcome.status == .ok)
        // refreshFleetPulse() runs the live hub census — hermetic model lands
        // on unknown, but the stale detail is overwritten either way.
        #expect(model.fleetPulse.detail != "stale")
    }

    // MARK: - Snapshot curation

    @Test("snapshot names the service, mirrors the field, and never dumps payloads")
    func snapshotCuration() async throws {
        let model = makeModel(recentQueries: ["recall fleet observe", "project.state"])
        model.fieldQuery = "recall fleet"
        model.lastOutcome = .recalled(hits: [
            MemoryHit(narrative: "first", source: .hotStore, score: 10.0),
            MemoryHit(narrative: "second", project: "andromeda", source: .vault, score: 8.0),
        ])
        model.fleetPulse = HUDFleetPulse(status: .yellow, attentionCount: 2, detail: "host degraded")

        let snapshot = try await HUDModelAppControlSource(model: model).snapshot()

        #expect(snapshot.service == "AndromedaHUD")
        #expect(snapshot.version == AppControlSnapshot.contractVersion)
        #expect(snapshot.query == "recall fleet")
        #expect(snapshot.outcome.kind == "recalled")
        #expect(snapshot.outcome.hits == 2)
        #expect(snapshot.recentQueries == ["recall fleet observe", "project.state"])
        #expect(snapshot.fleetPulse.status == "yellow")
        #expect(snapshot.fleetPulse.attentionCount == 2)
        #expect(snapshot.showsResultsPanel == true)
        // Capability curtain: hit narratives never ride the snapshot.
        let encoded = String(data: try JSONEncoder().encode(snapshot), encoding: .utf8) ?? ""
        #expect(!encoded.contains("first"))
        #expect(!encoded.contains("second"))
    }

    @Test("snapshot outcome summaries cover every HUDOutcome kind")
    func outcomeSummaries() {
        let pairs: [(HUDOutcome, String, String?)] = [
            (.idle, "idle", nil),
            (.syncing, "syncing", nil),
            (.recalled(hits: []), "recalled", "0 memory hits"),
            (.stored(idSummary: "abc123"), "stored", "abc123"),
            (.journaled(idSummary: "j-1"), "journaled", "j-1"),
            (.created(title: "New item"), "created", "New item"),
            (.updated(title: "Old item"), "updated", "Old item"),
            (.empty(message: "nothing matched"), "empty", "nothing matched"),
            (.failed(message: "boom"), "failed", "boom"),
        ]
        for (outcome, kind, summaryFragment) in pairs {
            let summary = HUDModelAppControlSource.summarize(outcome)
            #expect(summary.kind == kind)
            if let fragment = summaryFragment {
                #expect(summary.summary.contains(fragment))
            }
        }
        // Projects + chainHealth carry counts / status without rosters.
        let projects = HUDModelAppControlSource.summarize(.projects(states: []))
        #expect(projects.kind == "projects")
        #expect(projects.projects == 0)
    }

    @Test("snapshot round-trips Codable — the wire contract is stable")
    func codableRoundTrip() async throws {
        let model = makeModel(recentQueries: ["q1", "q2"])
        model.lastOutcome = .empty(message: "No memories matched “xyz”")

        let snapshot = try await HUDModelAppControlSource(model: model).snapshot()
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(AppControlSnapshot.self, from: data)

        #expect(decoded == snapshot)
        // Non-optional fields decode (no key drift).
        #expect(decoded.capturedAt > 1_700_000_000)
    }

    // MARK: - Screenshotter

    @Test("screenshotter renders PNG bytes from the live view tree")
    func screenshotRendersPNG() async throws {
        let model = makeModel()
        let png = try await HUDViewAppControlScreenshotter(model: model).pngData()

        // PNG magic bytes — proof the renderer produced a real image.
        #expect(png.count > 8)
        #expect(Array(png.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }
}

/// Synchronous notification observer — selector-based delivery means `fired`
/// is truth the moment `post` returns (no runloop spin needed).
@MainActor
private final class NotificationFlag: NSObject {
    private(set) var fired = false

    init(name: Notification.Name) {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(caught),
            name: name,
            object: nil
        )
    }

    @objc private func caught(_ notification: Notification) {
        fired = true
    }

    func remove() {
        NotificationCenter.default.removeObserver(self)
    }
}
