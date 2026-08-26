# AndromedaOrchestrator — SwiftUI export

The MCP service / LLM orchestrator console, ported from the HTML design to
SwiftUI. Swift 6 language mode, strict concurrency, `@Observable` state,
iOS 17 / macOS 14 minimum.

```
swiftui-export/
├── Package.swift
├── Sources/AndromedaOrchestrator/
│   ├── OrchestratorTheme.swift      palette (both schemes), type, motion, panel
│   ├── AndromedaMark.swift          angular trefoil shape + living mark view
│   ├── StatusVocabulary.swift       status enum, badges, TypedText, entrance
│   ├── OrchestratorModels.swift     domain values + demo fixtures
│   ├── OrchestratorModel.swift      @Observable console state machine
│   ├── LaunchRevealView.swift       the launch-out-of-the-HUD reveal
│   ├── OnboardingFlow.swift         four-beat first run + FlowLayout
│   ├── ConsoleControls.swift        buttons, nav rows, metrics, sparkline
│   ├── OrchestratorConsole.swift    shell: header · sidebar · screen · overlays
│   ├── ConsoleScreens.swift         overview · registry · providers
│   ├── TelemetryScreens.swift       usage & telemetry · v1 gateway
│   ├── StatesScreen.swift           six canonical states
│   ├── AddResourceSheet.swift       add-a-model / add-an-MCP-server wizard
│   ├── HUDPanel.swift               HUD + detached macOS NSPanel
│   └── Resources/andromeda-mark.png
├── OrchestratorCatalogue.swift     28 named specimens — one registry
│                                  (brand · vocabulary · controls · HUD ·
│                                  screens · flows) that the gallery, the
│                                  snapshot sweep, and the docs all read
├── OrchestratorGallery.swift      the browsable wall of specimens
├── Tests/AndromedaOrchestratorTests/
│   ├── PreviewParitySnapshotTests.swift   every #Preview gets a twin
│   ├── CatalogueSnapshotTests.swift       per-specimen sweep
│   └── OrchestratorSnapshotSupport.swift  hosting + record mode + fixtures
└── Examples/AndromedaOrchestratorApp.swift
```

## Getting it on screen

```swift
OrchestratorConsole(model: OrchestratorModel(), scheme: .dark)
```

`OrchestratorModel(firstRun: false)` skips straight to the console.
`Examples/AndromedaOrchestratorApp.swift` is a drop-in `App` with a
`MenuBarExtra` HUD. Every view has `#Preview`s in both schemes.

## Design rules encoded here

**The mark is angular, never a circle.** `AndromedaTrefoil` is the triangle /
obscured-diamond silhouette, ported from the same path as the HTML. Every
orbital, loader, halo, and HUD core uses it. `Resources/andromeda-mark.png`
is the pixel-accurate glyph; the shape is the fallback so previews never
render an empty frame.

**Light mode is a peer, not an afterthought.** `OrchestratorPalette` ships
`.obsidian` and `.observatory`, both derived from the same hues in
`web/app/globals.css`. Read it from the environment (`@Environment(\.palette)`)
after applying `.orchestratorPalette()` — never hardcode a `Color`. Light-mode
accents are darkened for contrast on white rather than reused from dark.

**Status is never color alone.** `OrchestratorStatus` bundles hue + glyph
(● ◐ ◯ ○) + word, and `StatusBadge` always renders at least the glyph and the
label. A test enforces it. Only unstable states pulse — a healthy row sits
still.

**One entrance curve.** `OrchestratorMotion.entrance` plus `.entrance(index)`
gives the cascading rise-and-settle used throughout; `OrchestratorMotion.stagger`
computes the per-row delay. Every animation checks
`@Environment(\.accessibilityReduceMotion)` and resolves to a still, complete
frame when it's on.

**Fonts.** Space Grotesk · Instrument Serif · JetBrains Mono, via
`OrchestratorFont`. Add the faces to `Resources/Fonts` and register them in
the host app's `Info.plist` (`ATSApplicationFontsPath`) — until then SwiftUI
falls back to the system face and previews still lay out correctly.

## Concurrency

State is `@MainActor @Observable`. The live request stream and the wizard's
probe are `async` methods driven by `.task`, so they cancel with the view —
no retained `Timer`, no `DispatchQueue`. Domain types are `Sendable`.

## Notes for the implementer

- `SampleData` is demo fixtures, deliberately named as such. Swap it for the
  real telemetry source; no view reads anything else.
- The launch reveal's fly-out offset (`x: 300, y: 268`) assumes the HUD sits
  bottom-right. Feed it the real HUD frame when wiring to the live panel.
- `HUDWindowController` is the detached macOS panel: non-activating, floating,
  joins all spaces. Docked and detached render the identical `HUDPanel`.
- `Sparkline` and `ShareBar` are `accessibilityHidden` — the adjacent numbers
  carry the value.
