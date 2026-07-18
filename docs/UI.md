# UI Surface — Menu-bar Module + Floating Pet + Modern HUD

Three SwiftUI surfaces over shared capability clients. **CommandCenter** is the deep utility panel; the **Pet** is the ambient delightful face; the **Andromeda HUD** is the modern floating control pill (BIN-55). None of them invent backend — they read artifacts / call stable capability IDs the pipeline already exposes.

## Shared client: `MultiBrainClient` (Swift)

One source of truth utility surfaces depend on. Zero business logic in the views.

- **Reads:** `~/.multibrain/health.json` (via `DispatchSource` file-watch → live status), today's Daily Brief note, `graphify-out/graph.html` path, `last-success` marker.
- **Talks to:** Letta REST API (chat + `generate_*`), graphify/LadybugDB MCP (query).
- **Publishes** (`@Observable`): `status: .idle | .working | .degraded(reason) | .newBrief`, `brief: DailyBrief?`, `recentLearnings: [SessionNote]`, `sources: [SourceStatus]`.

## Surface A — CommandCenter module (utility)

Extend the existing menu-bar app at `~/Documents/Developer/CommandCenter` using its InfraModule pattern. MemoryKit ships a proof-quality `CommandCenterView` (`@Observable`, badges, stub intents).

## Surface B — Floating Pet (delight)

A standalone companion: `MenuBarExtra` + optional always-on-top borderless window. MemoryKit ships `FloatingPetView` with idle / syncing / dreaming / degraded ambient states and reduce-motion static fallback.

## Surface C — Andromeda HUD (modern floating control)

**Module:** `AndromedaHUD` — see [ANDROMEDA-HUD.md](ANDROMEDA-HUD.md).

Modern macOS floating Head-Up Display (BIN-55 epic):

| Piece | Issue | Status |
| --- | --- | --- |
| Borderless draggable material pill (`NSPanel`) | BIN-60 | Foundation |
| Ice-style menu-bar snap | BIN-56 | Geometry + settle |
| Expandable Ask AI / `memory.*` search | BIN-57 | Router + UI |
| `@Observable` polish + SnapshotTesting | BIN-58 | Model + macOS snapshots |
| Sub-16ms / sub-50ms budgets | BIN-59 | Stopwatch proofs |

- **Collapsed:** drag handle · health glyph · **Andromeda** brand · Ask AI.
- **Expanded:** Screendrop-inspired field → `memory.recall` / `memory.store` / `memory.journal` / `infer.write`.
- **Capability curtain:** never Linear / Multica / provider brands in chrome.
- **Visibility:** explicit present/dismiss via `AndromedaHUDWindowController` — not a hidden LaunchAgent.

## Tech

- Swift 6 / SwiftUI, macOS. `MenuBarExtra` (menu-bar), borderless `NSPanel` / `WindowGroup` with `.level(.floating)` for Pet + HUD.
- HUD portable logic (snap, search, budgets, `@Observable` model) compiles and tests on Linux; AppKit chrome is `#if canImport(AppKit)`.
- File-watch on `health.json` for push-free live updates; poll Letta lightly for chat/status.
- No secrets in the app — it only reads local artifacts + hits localhost Letta/MCP / Andromeda gateway.
- Reuse the existing Swift toolchain; build for the Mac it runs on.

## Sequencing

1. `MultiBrainClient` + `health.json` file-watch (the shared spine).
2. CommandCenter `MultiBrainModule` (utility, fastest value).
3. Pet app (delight), reusing the client + shared popover views.
4. **Andromeda HUD** modern floating pill (BIN-55) — foundation landed; wire live `memory.*` next.
