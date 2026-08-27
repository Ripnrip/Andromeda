import SwiftUI

// MARK: - Gallery
//
// The browsable library: every catalogue specimen on one scrollable wall,
// grouped by shelf. Same view the snapshot sweep records, so what you browse
// is exactly what regression-checks.

/// One specimen on the wall: name plate above the specimen, panel-framed.
public struct SpecimenFrame: View {
    @Environment(\.palette) private var palette

    public let name: String
    public let specimen: AnyView

    public init(name: String, specimen: AnyView) {
        self.name = name
        self.specimen = specimen
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(name)
                .font(OrchestratorFont.mono(10, .semibold))
                .foregroundStyle(palette.muted)
                .textCase(.uppercase)
            specimen
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .panel()
    }
}


/// One gallery shelf: kicker + an EAGER wall of specimen frames in fixed
/// three-across rows. The wall is intentionally not lazy — 28 fixed
/// specimens gain nothing from deferred materialization, while lazy
/// containers never materialize offscreen (Xcode canvas pre-heat, snapshot
/// hosts), where they render as an empty void. Eager is deterministic
/// everywhere.
private struct GalleryShelf: View {
    @Environment(\.palette) private var palette

    let specimens: [OrchestratorSpecimen]

    private let columns = 3
    private let spacing: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(name)
                .font(OrchestratorFont.kicker(10))
                .foregroundStyle(palette.dim)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(row) { specimen in
                            SpecimenFrame(name: specimen.name, specimen: specimen.view)
                                .frame(maxWidth: .infinity)
                        }
                        // Keep ragged last-row cards at column width instead of
                        // letting HStack stretch them across the missing slots.
                        ForEach(0..<(columns - row.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    private var name: String {
        specimens.first?.group.rawValue ?? ""
    }

    private var rows: [[OrchestratorSpecimen]] {
        stride(from: 0, to: specimens.count, by: columns).map {
            Array(specimens[$0..<min($0 + columns, specimens.count)])
        }
    }
}

/// The full gallery wall — brand, vocabulary, controls, HUD, screens, flows.
public struct OrchestratorGallery: View {
    @Environment(\.palette) private var palette

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                ForEach(OrchestratorGroup.allCases) { group in
                    GalleryShelf(specimens: OrchestratorCatalogue.specimens(in: group))
                        .entrance(0)
                }
            }
            .padding(28)
            .frame(maxWidth: 1_280)
            .frame(maxWidth: .infinity)
        }
        .background(palette.void)
    }
}

#Preview("Gallery · obsidian") {
    OrchestratorGallery()
        .frame(width: 1_280, height: 900)
        .orchestratorPalette()
}

#Preview("Gallery · light") {
    OrchestratorGallery()
        .frame(width: 1_280, height: 900)
        .environment(\.colorScheme, .light)
        .orchestratorPalette()
}
