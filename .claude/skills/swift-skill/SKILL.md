---
name: swift-skill
description: Andromeda Swift canon — Swift 6 concurrency, strict review discipline, truthful product surfaces, snapshot/gallery rules, SwiftUI/TCA/SPM/Hummingbird craft, and repo-specific merge hygiene. Use for serious Swift/iOS/macOS review and implementation.
---

# Andromeda Swift Canon

**Swift 6 implementation + review canon** for iOS 17+, macOS 14+, watchOS 10+, and the Andromeda repo specifically.

Use this when the ask is not just “write Swift,” but “write and review Swift without lying, scope-creeping, or breaking Swift 6 rules.”

**Pairing rule**

```text
Domain/product truth (what Andromeda means) → domain skill / repo docs
Swift craft + review law (how to build and review it) → this skill
```

This canon explicitly covers:

- Swift 6 strict concurrency / `Sendable` / actor isolation / static-state pitfalls
- compile-first PR slicing and package-boundary discipline
- truth-in-UI / truth-in-product-surface review
- snapshot-testing discipline and PR gallery proof rules
- Andromeda repo rules: Swift-first, no bash implementation surface, visible and honest status
- merge hygiene: no unresolved substantive comments, no greenwash, no blob PRs

## Defaults

| Area | Standard |
|------|----------|
| Language | Swift 6, strict concurrency |
| UI | SwiftUI first; AppKit/UIKit bridges when needed |
| Architecture | TCA 1.15+ for complex state; `@Observable` for clients |
| Async | `async`/`await` + `AsyncStream`; Combine at legacy boundaries |
| Testing | swift-testing + SnapshotTesting + TestStore |
| Server | Hummingbird 2.x |
| Observability | OpenTelemetry Swift + os.Logger |

## Andromeda-specific non-negotiables

1. **Truth beats demo gloss.** Never represent spec, stub, or placeholder state as shipped reality.
2. **Capability names beat provider names.** Do not leak provider brands, raw model names, or secret-bearing implementation details into client-facing UI where the repo doctrine says they stay behind the curtain.
3. **Compile-first before product-expansion.** Fix green-ness and package integrity before broadening into design-system, UI, or product-surface work.
4. **No bash implementation surface.** If the repo can solve it in Swift, solve it in Swift.
5. **No merge with unresolved substantive review comments.** Reply, fix, resolve, then merge.

## Workflow

### New feature
1. `references/functional-swift.md` — pure core, effect shell
2. `references/concurrency.md` — Sendable, actors, streams
3. `references/tca.md` OR `references/swiftui-state.md` — pick architecture
4. `references/swiftui-views.md` — compose views
5. `references/previews.md` — state matrix before full builds
6. `references/testing.md` — unit + snapshot + TestStore
7. `references/andromeda-review-canon.md` — scope, truth, gallery, merge law

### SwiftUI surface
1. `references/swiftui-state.md` — property wrappers, `@Observable`
2. `references/swiftui-views.md` — extraction, performance, lists, sheets
3. `references/animations.md` — motion, transitions, keyframes
4. `references/motion-haptics.md` — haptics + Reduce Motion
5. `references/accessibility.md` — VoiceOver, Dynamic Type
6. `references/liquid-glass.md` — iOS 26+ (when requested)

### Platform extension
1. `references/platform-extensions.md` — App Intents, TipKit, WidgetKit, watch
2. `references/macos-patterns.md` — MenuBarExtra, floating windows, NSStatusItem

### Server / telemetry
1. `references/hummingbird.md`
2. `references/opentelemetry.md`
3. `references/combine.md` — only for legacy publisher bridges

## Quick rules

### State
- `@State` private; `@Binding` only when child **mutates** parent
- iOS 17+: `@Observable` + `@State` for owned; `@Bindable` for injected bindings
- Never pass values into `@State` / `@StateObject` initializers from outside

### Concurrency
- `@MainActor` for UI mutation
- `Sendable` across task boundaries
- `withTaskGroup` for parallel independent I/O
- Bridge Combine → `AsyncStream` at client boundary — never in reducers
- Treat Swift 6 compiler warnings/errors about sendability as design feedback, not noise
- Static tables in Swift 6 must either hold `Sendable` value types or be isolated appropriately

### Product truth / surface honesty
- Do not show provider model brands when the product contract says clients see capability aliases
- Do not invent storage layers, secret brokers, doctor success states, or "live" skills if those are not real
- Demo/sample rows must be clearly demo/sample, or neutral/spec-only placeholders
- If a surface is speculative, mark it `spec` / `planned` / `unwired` rather than implying reality

### PR scope discipline
- Gate / compile / packaging fixes stay narrow
- Product-truth cleanups, design refinements, and broader UX changes belong in follow-up PRs when they exceed the gate
- Never smuggle a design-system rollout into a compile-fix PR

### Snapshot / proof discipline
- Snapshot/UI PRs must include a **gallery in the PR body**, not just a comment
- Use repo-backed image paths or committed gallery assets — never private artifact URLs
- Be explicit whether images are **recorded snapshot baselines** or **package-surface proofs for review**
- If a PR has no visual/UI changes, do not run snapshot suites by default just because snapshots exist

### Review hygiene
- Answer every substantive review thread point-by-point
- Resolve threads only after the code or scope disposition actually addresses them
- Never merge while substantive unresolved comments remain, even if GitHub only shows “commented”

### SwiftUI performance
- Extract subviews; keep `body` pure
- `.animation(_:value:)` with value parameter
- Stable `ForEach` identity — never `.indices` for dynamic data
- Prefer transforms over layout animation

### TCA
- `@Reducer` + `@ObservableState`
- Clients: `Sendable` struct + `liveValue` / `testValue`
- Effects: `.run` with capture lists; `.cancellable(id:)` for streams

## Review checklist

- [ ] Strict concurrency — no data races
- [ ] `Sendable` / actor isolation / static data all satisfy Swift 6 rules
- [ ] Business logic out of `body` and out of views
- [ ] `#Preview` per major visual state
- [ ] Accessibility: `Button` not `onTapGesture`; labels on custom controls
- [ ] Reduce Motion fallbacks for motion
- [ ] No deprecated APIs (`references/latest-apis.md`)
- [ ] Tests: pure functions + TestStore + snapshots where UI matters
- [ ] UI/product copy does not over-claim shipped reality
- [ ] Client-facing surfaces do not leak provider brands or secret-bearing internals
- [ ] PR scope matches the stated gate / issue boundary
- [ ] Snapshot/UI PR body contains real gallery proof when visuals changed
- [ ] No merge with substantive unresolved comments

## References

| Doc | Topic |
|-----|-------|
| `functional-swift.md` | Pure transforms, composition, Result |
| `concurrency.md` | Swift 6, actors, AsyncStream, Sendable |
| `combine.md` | Publisher bridges, operators |
| `tca.md` | Reducers, clients, TestStore |
| `swiftui-state.md` | Property wrappers, data flow |
| `swiftui-views.md` | Composition, lists, sheets, performance |
| `animations.md` | Implicit/explicit, phase, keyframe |
| `motion-haptics.md` | UIImpactFeedback, NSHapticFeedback, motion a11y |
| `accessibility.md` | VoiceOver, Dynamic Type, announcements |
| `previews.md` | `#Preview`, `@Previewable`, fixtures |
| `testing.md` | swift-testing, snapshots, TestStore |
| `platform-extensions.md` | App Intents, TipKit, WidgetKit, ActivityKit |
| `macos-patterns.md` | MenuBarExtra, NSWindow, NSStatusItem |
| `hummingbird.md` | Router, middleware, testing |
| `opentelemetry.md` | Bootstrap, spans, metrics, exporters |
| `liquid-glass.md` | iOS 26 glassEffect |
| `latest-apis.md` | Deprecation migration table |
| `spm.md` | Package layout, dependencies |
| `anima-delegation.md` | When to switch to anima-swift |
| `andromeda-review-canon.md` | Andromeda-specific truth, scope, gallery, and merge rules |

## Pairing with repo/domain context

```
Domain/product (what)     → repo docs / domain skill
Craft + review law (how)  → swift-skill (this)
```

Example: a MemoryKit or control-plane PR may need repo docs for product truth, but this skill is where the Swift 6, snapshot, scope, and merge discipline live.
