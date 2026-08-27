import SnapshotTesting
import SwiftUI
import Testing

@testable import AndromedaOrchestrator

/// The catalogue sweep: every specimen in `OrchestratorCatalogue` gets a
/// baseline, so no component can drift visually without a red test. The
/// gallery, the sweep, and the docs all read the same registry — a specimen
/// missing here is a component nobody can browse or regression-check.
///
/// Sweep sizes are per-group (brand, vocabulary, controls, HUD, screens,
/// flows) so each specimen sits in a frame that fits its natural size.
///
/// Record: `SNAPSHOT_TESTING_RECORD=1 swift test --filter CatalogueSnapshotTests`
/// (CI: tip the PR head with `[record-snapshots]`; baselines are runner-image-bound.)
@Suite(.serialized, .snapshots(record: OrchestratorSnapshotSupport.recordMode))
@MainActor
struct CatalogueSnapshotTests {

    /// Sweep canvas size per gallery shelf.
    private static func size(for group: OrchestratorGroup) -> CGSize {
        switch group {
        case .brand:      CGSize(width: 220, height: 220)
        case .vocabulary: CGSize(width: 240, height: 90)
        case .controls:   CGSize(width: 360, height: 220)
        case .hud:        CGSize(width: 460, height: 320)
        case .screens:    CGSize(width: 600, height: 400)
        case .flows:      CGSize(width: 660, height: 520)
        }
    }

    private static func sanitized(_ name: String) -> String {
        name.replacingOccurrences(of: " · ", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
    }

    @Test("Catalogue specimen sweep", arguments: [
        OrchestratorGroup.brand, .vocabulary, .controls, .hud, .screens, .flows,
    ])
    func specimenSweep(group: OrchestratorGroup) throws {
        try OrchestratorSnapshotSupport.requireBaselines()
        let canvas = Self.size(for: group)
        for specimen in OrchestratorCatalogue.specimens(in: group) {
            let host = OrchestratorSnapshotHosting.makeHost(
                AnyView(specimen.view.orchestratorPalette()),
                canvas,
                dark: true
            )
            assertSnapshot(
                of: host,
                as: .orchestratorImage(precision: 0.98, perceptualPrecision: 0.96),
                named: Self.sanitized(specimen.name),
                file: #filePath,
                testName: "specimenSweep(\(group.rawValue))"
            )
        }
    }
}
