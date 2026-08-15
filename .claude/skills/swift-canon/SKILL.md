---
name: swift-canon
description: General Swift canon for any project — Swift 6 concurrency, actors, Sendable, enums, logging, SF Pro typography, SwiftUI, previews, animations, haptics, snapshot tests, TCA, SPM, Hummingbird, and Swift OpenAPI generated-code discipline.
---

# Swift Canon

**Project-agnostic Swift implementation + review canon** for iOS 17+, macOS 14+, watchOS 10+, and modern server-side Swift.

Use this when the ask is not just “write Swift,” but “write and review Swift cleanly under Swift 6, platform-native UI rules, and strong testing discipline.”

This canon explicitly covers:

- Swift 6 strict concurrency / `Sendable` / actor isolation / static-state pitfalls
- enums, exhaustive switches, associated-value design, unknown/default handling
- `os.Logger`, structured logging, and emoji log conventions
- SF Pro and platform-native typography defaults
- SwiftUI, Xcode previews, animation, haptics, and accessibility
- snapshot-testing, deterministic rendering, and preview/test matrices
- TCA, async streams, client design, package boundaries, Hummingbird, and Swift OpenAPI generation
- PR and review discipline that generalizes across Swift repos

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

## General non-negotiables

1. **Compiler truth first.** Swift 6 sendability, actor-isolation, and exhaustiveness errors are design feedback, not cosmetic lint.
2. **Native over ornamental.** Prefer platform conventions, SF Pro, system controls, and standard accessibility behavior before custom chrome.
3. **Generated code stays generated.** Never hand-edit generated OpenAPI output; extend at adapters/wrappers.
4. **Tests should match the change.** Snapshot/UI burden when visuals changed; behavioral tests when logic changed; no fake confidence from the wrong layer.
5. **No merge with unresolved substantive review comments.** Reply, fix, resolve, then merge.

## Workflow

### New feature
0. `references/anti-patterns.md` — DO NOT WRITE LIKE THIS; read before writing
1. `references/functional-swift.md` — pure core, effect shell
2. `references/concurrency.md` — Sendable, actors, streams
3. `references/enum-design.md` — enum modeling, exhaustive switch discipline
4. `references/logging.md` — `os.Logger`, structured logs, emoji log usage
5. `references/typography.md` — SF Pro, text hierarchy, platform-native typography
6. `references/tca.md` OR `references/swiftui-state.md` — pick architecture
7. `references/swiftui-views.md` — compose views
8. `references/previews.md` — state matrix before full builds
9. `references/testing.md` — unit + snapshot + TestStore
10. `references/review-canon.md` — generic PR, scope, and merge law

### SwiftUI surface
1. `references/swiftui-state.md` — property wrappers, `@Observable`
2. `references/swiftui-views.md` — extraction, performance, lists, sheets
3. `references/animations.md` — motion, transitions, keyframes
4. `references/motion-haptics.md` — haptics + Reduce Motion
5. `references/typography.md` — SF Pro, hierarchy, metrics
6. `references/accessibility.md` — VoiceOver, Dynamic Type
7. `references/liquid-glass.md` — iOS 26+ (when requested)

### Platform extension
1. `references/platform-extensions.md` — App Intents, TipKit, WidgetKit, watch
2. `references/macos-patterns.md` — MenuBarExtra, floating windows, NSStatusItem

### Server / telemetry
1. `references/hummingbird.md`
2. `references/opentelemetry.md`
3. `references/combine.md` — only for legacy publisher bridges
4. `references/openapi-server.md` — Swift OpenAPI generator, generated boundaries, Hummingbird/server integration

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

### Enums
- Prefer enums over stringly-typed status values
- Use associated values when payload belongs to the case
- Design for exhaustive switches; avoid defaulting away meaning unless forward-compat truly requires it
- For SDK / generated / external enums, be explicit about unknown-case handling

### Anti-patterns (`references/anti-patterns.md`)
- Never `@unchecked Sendable` on value types — fix the payload instead
- Never hand-roll JSON serialization — `JSONEncoder`/`JSONDecoder`, `.sortedKeys` for determinism
- Drain child pipes before awaiting exit; never iterate `.bytes` per-byte for bulk reads
- If a `try?` probe order is load-bearing, document it and test it

### Logging
- Default to `os.Logger` for app/server logging
- Log structure and intent, not prose sludge
- Emoji prefixes are fine when they add fast-scanning meaning, but they must stay consistent and not replace real metadata
- No secrets, tokens, or sensitive payload dumps in logs

### Typography
- Prefer SF Pro and system typography unless brand requirements explicitly override it
- Use semantic hierarchy first (`largeTitle`, `title`, `headline`, `body`, `caption`)
- Avoid arbitrary font stacks and decorative type unless the product truly calls for it

### PR scope discipline
- Compile/package fixes stay narrow
- Refactor, product-surface cleanup, server-contract changes, and design changes should be separate when they blur review truth
- Never smuggle a rollout into a green-the-build PR

### Snapshot / proof discipline
- Snapshot/UI PRs must include a **gallery in the PR body**, not just a comment
- Use repo-backed image paths or committed gallery assets — never private artifact URLs
- Be explicit whether images are **recorded snapshot baselines** or **review renders / proofs**
- If a PR has no visual/UI changes, do not run snapshot suites by default just because snapshots exist

### Generated code / OpenAPI
- Never hand-edit generated files
- Keep generated client/server surfaces in dedicated modules or folders
- Regeneration should be deterministic and repeatable from spec + plugin config
- Hand-written adapters should wrap generated shapes, not fork them

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
- [ ] Enum modeling is clean and switch coverage is honest
- [ ] Logging is structured, non-secret-bearing, and not noisy theater
- [ ] Business logic out of `body` and out of views
- [ ] Typography is platform-native unless deliberately overridden
- [ ] `#Preview` per major visual state
- [ ] Accessibility: `Button` not `onTapGesture`; labels on custom controls
- [ ] Reduce Motion fallbacks for motion
- [ ] No deprecated APIs (`references/latest-apis.md`)
- [ ] No canon anti-patterns (`references/anti-patterns.md`)
- [ ] Tests: pure functions + TestStore + snapshots where UI matters
- [ ] PR scope matches the stated gate / issue boundary
- [ ] Snapshot/UI PR body contains real gallery proof when visuals changed
- [ ] Generated code boundaries are respected; no hand edits in generated output
- [ ] No merge with substantive unresolved comments

## References

| Doc | Topic |
|-----|-------|
| `functional-swift.md` | Pure transforms, composition, Result |
| `concurrency.md` | Swift 6, actors, AsyncStream, Sendable |
| `enum-design.md` | Enum modeling, exhaustive switches, associated values |
| `anti-patterns.md` | DO NOT WRITE LIKE THIS — real exhibits with canon fixes |
| `logging.md` | `os.Logger`, structured logs, emoji log conventions |
| `typography.md` | SF Pro, hierarchy, typography review rules |
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
| `openapi-server.md` | Swift OpenAPI generation, contracts, Hummingbird integration |
| `opentelemetry.md` | Bootstrap, spans, metrics, exporters |
| `liquid-glass.md` | iOS 26 glassEffect |
| `latest-apis.md` | Deprecation migration table |
| `spm.md` | Package layout, dependencies |
| `review-canon.md` | Generic PR, scope, gallery, and merge rules |

## Scope boundary

```
Project/domain specifics  → project docs / project skill
Swift craft + review law  → swift-canon (this)
```

If a repo has extra rules, layer them on top of this canon. This skill is the reusable base.
