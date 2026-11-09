# Swift & Apple Platform UI Design Resource

> Unified craft standard for Claude Design when designing, prototyping, or implementing native macOS, iOS, iPadOS, and visionOS interfaces.
> Integrates **Drivable UI**, **Hot Reload (Inject)**, **Xcode Previews**, **SF Symbols & Typography**, **Fleet Swift Canon**, and the **15-Question Review Gate**.

---

## 1. Core Mission & Philosophy

When Claude Design works in native Apple platforms (Swift & SwiftUI), the design process must maintain high visual taste while strictly adhering to production Apple engineering discipline.

- **Fidelity to Platform**: Look and feel like a first-class Apple citizen. Deployment baseline matches the fleet manifests: **macOS 14 / iOS 17** — newer APIs are availability-gated (`if #available`), never a deployment-target bump.
- **Zero AI Slop**: No generic centered heroes on monitor surfaces, no unearned blur/glassmorphism, no artificial card grids.
- **Instrumentable & Drivable**: Designed from the start so autonomous agents, tests, and CI can inspect and drive the interface exactly like a human click.
- **Instant Iteration Loop**: Live preview matrices with Xcode Previews, hot reload via Inject in Debug, snapshot testing for pixel parity.

---

## 2. Drivable UI & App Control Architecture

> Distinct from the user-facing product Control Plane, **App Control** is the debug/test/agent harness adapter enabling programmatic inspection and interaction without brittle coordinate-based automation.

### The Three-Endpoint Contract

Every drivable surface or app container must expose or conform to this interface:

| Endpoint | Method | Payload / Response | Contract Rule |
| :--- | :--- | :--- | :--- |
| `/state` | `GET` | Curated JSON read model | Represents actual visual state. Honesty badges live here. **Never expose secrets/PII**. |
| `/action` | `POST` | Typed `ControlAction` JSON | Invokes **exactly** the methods and reducers triggered by human clicks. Unknown action = `422 Unprocessable`. |
| `/screenshot` | `GET` | PNG data stream | Off-screen render by identifier/pane. **Never use OS-level screen capture tools (`screencapture`)**. |

### Security & Gating (non-negotiable)

The contract above is a **debug/test harness, never a production control endpoint**. An app implementing these routes literally must carry the same constraints as the canonical App Control contract (`web/public/lessons/pack/app-control.md`):

- **Env gate**: routes exist only when `ANDROMEDA_APP_CONTROL=1` is set. Absent the flag, none of the three endpoints are registered.
- **Bind loopback only**, or authenticate via the existing MCP bearer — never an unauthenticated or non-loopback listener.
- **No second HTTP host**: extend the existing `AndromedaHTTP` router. Do not spin up a parallel server for App Control.

### Hierarchical Control Identifiers

Every interactive control and container must have a deterministic identifier:

- **Format**: `<domain>.<pane>.<component>.<action>`
  - Example: `andromeda.hud.search.field`
  - Example: `andromeda.controlplane.pillars.memory.toggle`
  - Example: `emerge.launcher.search.input`
- **Lists / Tables / Grids**: Rows must use **stable entity IDs**, never array index alone.
  - Correct: `andromeda.vault.entry.row.item-uuid-1234`
  - Incorrect: `andromeda.vault.entry.row.3`
- **Identifier ≠ Accessibility Label**: Both are mandatory.
  - `.accessibilityIdentifier("andromeda.hud.close.button")` (for agents, UI tests, and App Control)
  - `.accessibilityLabel("Close HUD")` (for VoiceOver and human assistive technology)

### Instrumentable UI Primitives

1. **Primitives are Dumb**: Layout components (`GlassCard`, `StatusDot`, `CommandBar`, `TabGroup`) take caller-supplied identifiers and closures. They do not initiate network calls or hold ambient state.
2. **Decorative Motion vs Interactive**: Decorative animations must be bypassable in snapshot/screenshot captures. Respect `@Environment(\.accessibilityReduceMotion)`.
3. **The Verification Triad**: A UI feature is verified only when:
   $$\text{State (Read Model)} \equiv \text{AX Tree (VoiceOver)} \equiv \text{Rendered Pixels (Snapshot/Screenshot)}$$

---

## 3. Hot Reload (`Inject`) in SwiftUI

> Enable sub-second visual iterations on live simulators and macOS apps using `krzysztofzablocki/Inject`.

### Setup & SPM / XcodeGen Configuration

In `project.yml` (XcodeGen) or `Package.swift`:

```yaml
packages:
  Inject:
    url: https://github.com/krzysztofzablocki/Inject.git
    from: "1.5.2"

targets:
  MyApp:
    type: application
    dependencies:
      - package: Inject
```

### Root View Wiring

Wire Inject in the root UI view instantiated inside `WindowGroup` in `@main App` (do not wire on the `App` or `Scene` struct itself):

```swift
import SwiftUI
#if DEBUG
import Inject
#endif

struct RootContentView: View {
    #if DEBUG
    @ObserveInjection private var inject
    #endif

    @State private var model = AppStateModel()

    var body: some View {
        MainNavigationView(model: model)
            #if DEBUG
            .enableInjection()
            #endif
    }
}
```

### 🚨 Critical Release Hygiene Gate

- **Never ship Inject in Release binaries**: `Inject` loads local bundles and injects dylibs at runtime. Leaving it enabled in Release triggers App Store rejection and bloats binary size.
- **Conditioning**:
  - Always guard `import Inject`, `@ObserveInjection`, and `.enableInjection()` with `#if DEBUG`.
  - In Xcode build settings, mark the Inject package dependency as conditional to Debug configuration where possible.
  - Verify Release archives with: `nm -u MyApp.app/MyApp | grep -i Inject` (must return zero results).

---

## 4. Xcode Previews & Snapshot Parity

> UI must be visually verifiable before running full builds. Every user-visible view requires an exhaustive preview matrix.

### The Mandatory State Matrix

For every public or user-visible view, provide previews covering the full matrix of visual states:

```swift
import SwiftUI

struct ServerStatusCard: View {
    let status: ServerStatus
    
    var body: some View {
        HStack(spacing: 12) {
            StatusDot(state: status.dotState)
            VStack(alignment: .leading, spacing: 4) {
                Text(status.title)
                    .font(.headline)
                Text(status.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("server.status.card")
    }
}

// MARK: - Previews Matrix

#Preview("Healthy - Light") {
    ServerStatusCard(status: .healthy(name: "Hermes Gateway", latencyMs: 14))
        .preferredColorScheme(.light)
        .padding()
}

#Preview("Degraded - Dark") {
    ServerStatusCard(status: .degraded(name: "Hermes Gateway", reason: "Rate limited"))
        .preferredColorScheme(.dark)
        .padding()
}

#Preview("Loading State") {
    ServerStatusCard(status: .connecting)
        .padding()
}

#Preview("Dynamic Type - Accessibility XXL") {
    ServerStatusCard(status: .healthy(name: "Hermes Gateway", latencyMs: 14))
        .environment(\.dynamicTypeSize, .accessibility2)
        .padding()
}

#Preview("Reduce Motion") {
    ServerStatusCard(status: .connecting)
        .environment(\.accessibilityReduceMotion, true)
        .padding()
}
```

### Interactive Previews (iOS 17+ / macOS 14+)

Use `@Previewable` for stateful interactions directly in the `#Preview` canvas:

```swift
#Preview("Interactive Filter Bar") {
    @Previewable @State var selectedFilter: FilterKind = .all
    @Previewable @State var query: String = ""

    FilterBar(selected: $selectedFilter, query: $query)
        .padding()
}
```

### Rules of Preview Craft

1. **Zero Live Networking**: Previews must never execute live network requests, make file system writes outside of scratch, or access system services like EventKit/Contacts without mock providers.
2. **Dedicated `PreviewSupport` Fixture Target**: Place mock data, stub clients, and preview helpers in a separate SPM target (`PreviewSupport`) that is never linked into production Release binaries.
3. **Point-Free Snapshot Parity**:
   - Every state in the preview matrix should be covered by automated snapshot tests via `swift-snapshot-testing` (`assertSnapshot(of: view, as: .image)`).
   - Commit baseline snapshots to `__Snapshots__/`.
   - Record baselines on CI/clean environments, not ad-hoc dirty host workspaces.

---

## 5. SF Symbols & Apple Typography Discipline

### SF Pro Typography System

Always use semantic text styles rather than hand-picked point sizes:

| Semantic Style | Typical Use |
| :--- | :--- |
| `.largeTitle` | Top-level screen title or hero headline (Decide/Learn surfaces only) |
| `.title` / `.title2` / `.title3` | Section headings, primary modal titles, pane titles |
| `.headline` | Card headers, table cell titles, primary entity names |
| `.body` | Standard paragraphs, content text, default inputs |
| `.callout` | Secondary callouts, contextual notices, hints |
| `.subheadline` | Metadata, subtitles, secondary descriptive lines |
| `.footnote` | Helper text, validation feedback, timestamp footers |
| `.caption` / `.caption2` | Badges, tags, small status labels |

#### Typography Rules:
- **Build Hierarchy with Weight and Layout First**: Use `.fontDesign(.monospaced)` only for code, hashes, and technical values; never across an entire product interface.
- **Dynamic Type**: Never constrain view heights with rigid frames (`.frame(height: 24)`) if they enclose text. Use layout guides, vertical padding, and `ViewThatFits` where truncation might occur.

### SF Symbols Best Practices

Apple's SF Symbols icon library provides unified iconography across macOS and iOS:

1. **Semantic Rendering Modes**:
   ```swift
   Image(systemName: "wifi.exclamationmark")
       .symbolRenderingMode(.hierarchical)
       .foregroundStyle(.orange)
   ```
   - `.monochrome`: Single flat tint.
   - `.hierarchical`: Single color with automated opacity steps for depth.
   - `.palette`: Multiple explicit colors mapped to icon layers (`.foregroundStyle(.blue, .gray)`).
   - `.multicolor`: Authentic system colors (e.g. green battery, yellow warning).

2. **Symbol Effects (iOS 17+ / macOS 14+)**:
   ```swift
   Image(systemName: "bell.badge")
       .symbolEffect(.bounce, value: notificationCount)
       .symbolEffect(.variableColor.iterative, isActive: isSyncing)
   ```

3. **Accessibility for Symbols**:
   - Symbols are visual representations; their accessibility labels must convey **action or state**, not the glyph name.
   - ❌ Bad: `Image(systemName: "speaker.slash.fill").accessibilityLabel("speaker slash fill")`
   - ✅ Good: `Image(systemName: "speaker.slash.fill").accessibilityLabel("Mute audio")`

---

## 6. Fleet Swift Coding Guidelines & Canon

### Core Identity & Language Standards
- **Target Modern Platforms**: Swift 6+ language mode. Deployment baseline **iOS 17 / macOS 14** (the fleet manifests); newer APIs must be availability-gated, not baseline-raising.
- **Protocol-Oriented & Value Types**: Structs over classes by default. Use actors for shared mutable state. Classes only when AppKit/UIKit interop strictly demands reference semantics.
- **Enums as First-Class State Machines**:
  - Model states, routes, errors, and configuration as typed `enum`s.
  - Conform to `CaseIterable` so tests and preview matrices can exhaustively iterate over every variant.
  - Never pass loose magic strings or arbitrary integers across internal boundaries.
- **Observation Framework (`@Observable`)**:
  - Prefer modern `@Observable` classes over legacy `ObservableObject` and `@Published`.
  - In views, consume observable models using plain `let` or `@State var model = ...`.
- **Swift 6 Concurrency**:
  - Strict concurrency checking enabled.
  - Ensure all data crossing concurrency boundaries conforms to `Sendable`.
  - Mark UI-bound models and views with `@MainActor`.
  - Avoid `@unchecked Sendable` unless wrapping proven thread-safe C/Obj-C pointers, and document the rationale with a comment.
- **Modern Swift Testing**:
  - Prefer Swift Testing (`import Testing`, `@Test`, `#expect(...)`) over legacy `XCTest`.
- **Verbose Emoji Telemetry**:
  - Internal logging and state transitions must emit structured telemetry with domain glyphs:
  - `📡` Network/RPC · `🔥` Critical/Error · `✅` Success · `⚠️` Warning · `🧪` Test/QA · `🏗️` Build/Config · `🔄` Cycle/Sync · `🛑` Terminate/Block.

---

## 7. The Fleet 15-Question Review Gate

Every Swift UI change or PR must satisfy these 15 questions. **Merge blockers are exactly Q1, Q2, Q6, Q8, Q9, and Q14** — identical to the canonical gate (`.claude/skills/swift-review-gate/SKILL.md`); this resource must never silently change fleet merge policy. All other questions are review-tier: each unchecked item needs an explicit rationale or `N/A` in the PR:

### Type & Expression
- **Q1 [BLOCKER] Enums over magic strings**: Every finite set (states, error kinds, allowlists, lanes) is an `enum` with exhaustive `switch`.
- **Q2 [BLOCKER] Codable on the wire**: No hand-built JSON string literals in production code. Wire models encode from types.
- **Q3 Smallest clear expression**: Honest cost of functions vs computed properties; prefer `switch` and `guard let` over chained `if`s.
- **Q4 Protocol vs enum**: Protocols only where implementations genuinely vary across modules or test boundaries; otherwise prefer an `enum`.
- **Q5 Functional Swift**: Use `map`/`compactMap`/`reduce` on pure collection transforms; preserve streaming loops when collecting would buffer or hide side effects.

### Concurrency & Streams
- **Q6 [BLOCKER] Actors & Sendable**: Shared mutable state is actor-isolated or `Sendable`. No unverified `@unchecked Sendable`.
- **Q7 Smallest honest lifetime model**: Use `async` functions for one-shot requests, `AsyncStream` for streams, and Combine only at real publisher boundaries.

### Observability & Security
- **Q8 [BLOCKER] Emoji telemetry**: Every major branch or decision point emits a typed event with standard emoji glyphs.
- **Q9 [BLOCKER] Secrets & data posture**: No secret leaks, no ambient environment inheritance, no PII in logs or mirrored states.

### UI & Presentation
- **Q10 Xcode Previews** *(review tier)*: Every user-visible state has a dedicated `#Preview` covering healthy, empty, error, dark mode, and Dynamic Type. Missing previews need an explicit rationale in the PR — they are a review-tier judgment, not a mechanical merge blocker (matches the canonical gate).
- **Q11 Snapshot tests**: Visual regressions covered by committed snapshot test baselines.
- **Q12 Interaction feedback**: Intentional haptics/sensory feedback on taps, accompanied by VoiceOver accessibility labels.

### Quality & Craft
- **Q13 Performance**: Allocation-conscious hot paths, no synchronous I/O or heavy operations on `@MainActor`.
- **Q14 [BLOCKER] Exhaustive proof**: Tests drive all `CaseIterable` variants; behavior is verified with real code execution.
- **Q15 Simpler shape**: Has unnecessary indirection, excess wrapper types, or speculative architecture been eliminated?

---

## 8. Anti-Patterns to Avoid

| ❌ Anti-Pattern | Why It Fails | ✅ Approved Replacement Shape |
| :--- | :--- | :--- |
| `AnyView(...)` | Destroys SwiftUI view identity, invalidates diffing engine, degrades performance. | Use `@ViewBuilder`, generic constraints, or enum-based subviews. |
| Hand-rolled JSON strings | Breaks wire stability; key ordering is non-deterministic; typo-prone. | Conform typed models to `Codable`. |
| Unconditional `import Inject` | Injects debug-only hot reload symbols into production Release binaries. | Wrap in `#if DEBUG ... #endif`. |
| Live networking in `#Preview` | Makes previews slow, flaky, dependent on network state, or creates side-effects. | Inject mock service protocols or static fixtures from `PreviewSupport`. |
| Rigid frame constraints | Breaks Dynamic Type when users increase system font sizes. | Use flexible padding, layout priorities, and `ViewThatFits`. |
| Force unwraps (`!`) in view bodies | Triggers immediate app crashes if data state changes unexpectedly. | Use `guard let`, `if let`, or safe default fallbacks. |
| Arbitrary notification sprawl | `NotificationCenter` creates untraced spooky action at a distance. | Use `@Observable` state, `@Binding`, or modern Swift Concurrency streams. |

---

## 9. Native Apple Surface Archetypes

Before writing a single line of SwiftUI, commit to the primary surface archetype:

1. **Monitor** (Dashboards, Status Bars, HUDs):
   - High information density, glanceable hierarchy, status indicators (`StatusDot`).
   - Never use marketing heroes or large promotional feature cards.
2. **Operate** (Control Planes, Toolbars, Action Panels, Queues):
   - Dominant action affordances, key command triggers, direct manipulation.
3. **Compare** (Spec sheets, plan comparisons, side-by-side inspectors):
   - Aligned columns, parity of structure, clear differential badges.
4. **Configure** (Settings, Preferences, Setup Wizards):
   - Clean forms, progressive disclosure, immediate validation feedback.
5. **Decide / Learn** (Landing views, Welcome sheets, Feature walkthroughs):
   - The *only* surface where a prominent hero or promotional header is appropriate.
6. **Explore** (Catalogs, Asset Libraries, Search Results):
   - Integrated search bars, adaptive grids, filter chips, detail inspectors.
7. **Command / Inspect** (Command Palette, Property Inspector, Spotlight-like tools):
   - Keyboard-driven, instant filtering, minimal decoration, maximum speed.

---

## 10. Deliverable Checklist for Claude Design

When delivering a native Swift/Apple UI artifact:
- [ ] Dedicated view file with modular subviews.
- [ ] Accessibility identifiers (`.accessibilityIdentifier(...)`) for App Control and test drivability.
- [ ] Accessibility labels (`.accessibilityLabel(...)`) for screen readers.
- [ ] `#if DEBUG` gated Inject hot-reload hook.
- [ ] Comprehensive `#Preview` matrix covering dark mode, empty/error states, and Dynamic Type.
- [ ] Adherence to SF Pro typography and SF Symbols best practices.
- [ ] Verification against the 15-Question Review Gate.
