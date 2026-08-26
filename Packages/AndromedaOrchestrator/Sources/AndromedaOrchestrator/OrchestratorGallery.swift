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

/// The full gallery wall — brand, vocabulary, controls, HUD, screens, flows.
public struct OrchestratorGallery: View {
    @Environment(\.palette) private var palette

    public init() {}

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 34) {
                ForEach(OrchestratorGroup.allCases) { group in
                    VStack(alignment: .leading, spacing: 16) {
                        Text(group.rawValue)
                            .font(OrchestratorFont.kicker(10))
                            .foregroundStyle(palette.dim)
                            .textCase(.uppercase)
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 300), spacing: 14)],
                            alignment: .leading,
                            spacing: 14
                        ) {
                            ForEach(OrchestratorCatalogue.specimens(in: group)) { specimen in
                                SpecimenFrame(name: specimen.name, specimen: specimen.view)
                            }
                        }
                    }
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
