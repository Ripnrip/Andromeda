# AndromedaUI

The SwiftUI design system for the Andromeda local-first control plane — palette,
motion, typography, reusable animations, event-driven memory components,
the real logo, and the Control Plane UI surfaces.

> Nested package under `Packages/AndromedaUI` (same dual-home pattern as MemoryKit / Anima).
> Canonical colour truth remains `AndromedaBrand` + `web/app/globals.css`; this package
> currently carries parallel SwiftUI aliases that BIN-271 will converge.

## Requirements

- iOS 17 · macOS 14 · tvOS 17 · watchOS 10
- Swift 6 / Xcode 16

## Install (in-repo)

```swift
.package(path: "Packages/AndromedaUI"),
// …
.product(name: "AndromedaUI", package: "AndromedaUI"),
```

Or build/test standalone:

```console
cd Packages/AndromedaUI && swift test
```

## Gate 0 compile fixes (BIN-270)

- Renamed floating-bar capability model to `BarPillar` (control-plane nav keeps `Pillar`)
- Single `Color.andromedaAmber` / `.andromedaDim` / `.andromedaInk` declarations in `AndromedaTheme`
- Explicit `ColorScheme` in `#Preview` / test hosts (Swift 6 inference)
- Stable `Identifiable` ids for static catalogs (`MemoryKind`, row models) — no `UUID()` stored props
- Snapshot suites skip until `__Snapshots__` baselines are recorded on macOS

## Foundations

- **Palette** — `Color.andromeda{Void, Panel, Teal, Glow, Live, Muted, Amber, Dim, Ink}`.
- **Motion** — `Motion.{pulse, breathe, orbit, sweep, wave}` + `Motion.spring(_:_:)`.
- **Typography** — `AndromedaFont.{serif, ui, mono}` + `.cpDisplay()/.cpTitle()/.cpBody()/.cpMeta()` view modifiers and `Eyebrow`.
- **Surface & mark** — `AndromedaSurface()`, `AndromedaLogo()` (bundled raster), `AndromedaCore()` (breathing + orbiting glyph).

## Control Plane

```swift
import AndromedaUI

ControlPlaneView()          // full window: sidebar + routed sections
```

Sections, each usable standalone:

- `MemorySection()` — scope tabs, salience map, storage layers, change feed, `MemoryKindsGrid`
- `ModelsSection()` — Models / Speed / Health tabs
- `SearchSection()` — Ask Andromeda (internal vs external)
- `CapabilityListSection(pillar:)` — MCP · Skills · Secrets · Fleet
- `SettingsSection(onLifecycle:)` — Setup · Doctor · Cleanup · About · Config

Shared kit: `StatusBadge`, `GlassCard`, `SegTab`, `AddButton`.

## Floating bar (menu-bar app)

`FloatingBarPanel` / `FloatingBarController` — draggable LSUIElement accessory hosting
`AndromedaBarContent`. Set `Application is agent (UIElement) = YES` in Info.plist.

## Tests

`swift test` — Point-Free snapshot coverage in `Tests/AndromedaUITests`:

- **`Gate0CompileSmokeTests`** / **`AndromedaCatalogueTests`** — always-on compile + catalogue checks
- **`ControlPlaneSnapshotTests`** — every section + primitive × {dark, light} (skips until baselines exist)
- **`ControlPlaneA11yTests`** — Dynamic Type snapshots + UIKit accessibility-tree labels
- **`AndromedaSnapshotTests`** — animation catalogue × {dark, light} (UIKit)

Baselines are recorded (119 PNGs, macos-15 + Xcode 16.4) — CI runs in compare
mode on every PR. Re-record only via a tip-commit subject marker on the runner
(see the record-detect step in `.github/workflows/ci.yml`).

## License

MIT.
