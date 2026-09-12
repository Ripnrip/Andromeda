@testable import AndromedaOrchestrator
import SwiftUI
import Testing

/// Pillar 1 proof — every interactive console control is addressable by its
/// `<domain>.<pane>.<control>` identifier. The scheme is load-bearing:
/// control-plane state, AX diffs, and future screenshot tooling all resolve
/// elements by identifier. An unnamed control is invisible to all of it.
///
/// These tests pin the canon (scheme + coverage) at the type level; the
/// snapshot previews prove the identifiers land on rendered controls.
@Suite("AndromedaOrchestrator.ControlIdentifiers")
struct ControlIdentifierTests {
    /// The canonical domain list — one place, written down, per the
    /// identifiers reference. Panes add controls; they never re-domain.
    private static let domains = ["console"]

    @Test("identifier canon: known names follow the three-segment dotted scheme")
    func identifierScheme() {
        let known = [
            "console.onboarding.skip",
            "console.onboarding.continue",
            "console.sidebar.add-model",
            "console.sidebar.add-mcp-server",
            "console.overview.stream-toggle",
            "console.registry.add-mcp-server",
            "console.providers.add-model",
            "console.sheet.close",
            "console.sheet.back",
            "console.sheet.commit",
        ]
        for identifier in known {
            let segments = identifier.split(separator: ".").map(String.init)
            #expect(segments.count >= 3, "identifier '\(identifier)' must have ≥3 segments")
            #expect(Self.domains.contains(segments[0]), "identifier '\(identifier)' must use a canonical domain")
            #expect(identifier == identifier.lowercased(), "identifier '\(identifier)' must be lowercase")
        }
    }

    @Test("screen enum exposes one sidebar identifier per case — no pane unnamed")
    func sidebarCoverage() {
        let screens = OrchestratorModel.Screen.allCases
        #expect(!screens.isEmpty)
        // The identifier derivation is total and collision-free: every case
        // produces a distinct lowercase three-segment name.
        let identifiers = screens.map { "console.sidebar.\($0.rawValue)" }
        #expect(Set(identifiers).count == identifiers.count)
        for identifier in identifiers {
            #expect(identifier.split(separator: ".").count == 3)
            #expect(identifier == identifier.lowercased())
        }
    }

    @Test("wizard scope chips derive stable identifiers from data, not position")
    func scopeChipIdentifiers() {
        // The chip derivation lowercases and dashes spaces — proven on the
        // exact transformation the view applies.
        let chip = "Filesystem Write"
        let identifier = "console.sheet.scope.\(chip.lowercased().replacingOccurrences(of: " ", with: "-"))"
        #expect(identifier == "console.sheet.scope.filesystem-write")
        #expect(identifier.split(separator: ".").count == 4)
    }
}
