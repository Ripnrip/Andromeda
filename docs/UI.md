# UI Surface — Menu-bar Module + Floating Pet

Two SwiftUI surfaces over one shared client. **Both** are shipped (locked decision): the CommandCenter module is the deep utility panel; the Pet is the ambient, delightful face. Neither adds backend — they read artifacts the pipeline already produces.

## Shared client: `MultiBrainClient` (Swift)

One source of truth both surfaces depend on. Zero business logic in the views.

- **Reads:** `~/.multibrain/health.json` (via `DispatchSource` file-watch → live status), today's Daily Brief note, `graphify-out/graph.html` path, `last-success` marker.
- **Talks to:** Letta REST API (chat + `generate_*`), graphify/LadybugDB MCP (query).
- **Publishes** (`@Observable`): `status: .idle | .working | .degraded(reason) | .newBrief`, `brief: DailyBrief?`, `recentLearnings: [SessionNote]`, `sources: [SourceStatus]`.

## Surface A — CommandCenter module (utility, ships first)

Extend the existing menu-bar app at `~/Documents/Developer/CommandCenter` using its InfraModule pattern. A `MultiBrainModule` menu section:

```
🧠 Multi-Brain            🟢
────────────────────────────
Health: green · last run 02:34
Sources: claude ✓ codex ✓ hermes ✓ multica ✓ vm ✗
────────────────────────────
Today's Brief
  Yesterday: 6 sessions, 3 projects…
  Insights Ahead: 4 open threads
────────────────────────────
▸ Open graph      ▸ Open vault
▸ Chat Librarian  ▸ Consolidate now
▸ Run healthcheck ▸ Dashboards ▾
```

- Status dot mirrors `health.json`; red shows the failing check inline.
- "Chat Librarian" opens a small Letta chat panel.
- "Consolidate now" triggers `run-nightly.sh` (with a spinner bound to `.working`).

## Surface B — Floating Pet (delight, ships second)

A standalone app: `MenuBarExtra` + an optional always-on-top borderless companion window.

- **Animated states** (the "dynamic and responsive" ask):
  - `idle` 😌 — calm idle loop, green tint.
  - `working` 🤔 — "thinking" animation while consolidation runs.
  - `degraded` 😱 — agitated + red; tap shows the failing check.
  - `newBrief` ✨ — a gentle badge/bounce when the morning brief lands.
- **Interactions:** click → popover with the brief + quick actions (same as the module, shared views); drag to reposition; right-click for settings.
- **Personality:** reacts to fabric events — perks up when many learnings land, naps on a quiet day, alarmed on degradation. Think Codex's pet, but wired to *your* brain's pulse.

## Tech

- Swift 6 / SwiftUI, macOS. `MenuBarExtra` (menu-bar), a borderless `NSWindow`/`WindowGroup` with `.level(.floating)` for the Pet.
- File-watch on `health.json` for push-free live updates; poll Letta lightly for chat/status.
- No secrets in the app — it only reads local artifacts + hits localhost Letta/MCP.
- Reuse the existing Swift toolchain (see the user's `swift-skill`); build for the Mac it runs on.

## Sequencing

1. `MultiBrainClient` + `health.json` file-watch (the shared spine).
2. CommandCenter `MultiBrainModule` (utility, fastest value).
3. Pet app (delight), reusing the client + shared popover views.
