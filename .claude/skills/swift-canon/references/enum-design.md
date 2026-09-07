# Enum Design

Enums are one of Swift's biggest strengths. Use them aggressively where state is finite and meaningful.

## Rules

- Prefer enums over loose strings/ints for state, mode, route, outcome, and lifecycle.
- Use associated values when payload belongs to the case.
- Keep the enum semantic: one case should mean one state.
- Avoid boolean pairs that imply hidden state matrices.
- **Type-shape decision rule (pick by the domain's shape, not vibes):**
  exclusive states → `enum` · combinable selection → `Set<RawEnum>` ·
  bitmask-hot-path → `OptionSet` · recursive structure → `indirect enum`.
  A selection of N combinable flags is a *subset*, not a state — an enum
  would need 2^N cases. `indirect` exists for recursion (ASTs, composite
  matchers, nested containers); modeling non-recursive data recursively is
  indirection with no domain fidelity. (Origin: the CIScope Scope debate,
  PR #65, Sep 2026.)
- **`CaseIterable` + associated values don't compose** — enums with
  associated values don't synthesize `allCases`. Split the roles: the
  matcher/AST enum owns the associated values (`.exact(path)` /
  `.prefix(path)`); the enumerable contract stays a rawValue enum driving
  iteration with exhaustive switches for effects.
- **Multi-match classification is not a single `switch`.** When one input
  can arm several rules (glob-fallthrough semantics), classification
  iterates typed rule cases; the compile-checked guarantees live in
  per-rule *effects* switches (`var lanes: [Lane]`), not in the loop shape.
- **Typed path vocabulary — no hand-spelled rule strings.** Path literals
  scattered through matchers are transliterated shell. Compose from a typed
  repo layout (`Package` with derived `root`/`manifest`/`resolved`/
  `sources`/`tests`; `RootModule` with declared tree membership) so each
  literal string exists exactly once.
- **Output contracts one-fact-one-place:** the enum's rawValue IS the
  external key; CaseIterable drives emission; adding a case without an
  output key no longer compiles.
- **Derived strings (labels, IDs, descriptions) go through exhaustive `switch` — never `rawValue` concatenation or interpolation.** Runtime concatenation (`"memory." + rawValue`) means renaming a case silently drifts every derived string; a `switch self` is compiler-checked and fails loudly on new cases.
- **Call sites reference `.rawValue` — never re-type a literal an enum already owns.** Hand-typed literals drift from the enum silently (`hasPrefix("infer.write")` when the enum says `case inferWrite = "infer.write"`). If the string is a stable contract, the enum declaration is its single source of truth.
- Enforced by `canon/ast-grep/` rules in CI (`enum-raw-value-concat`, `bare-capability-literal`); see anti-patterns Exhibit 6.
- **Behavior-preserving refactors prove themselves with A/B digests:** run the retired implementation and the rewrite against identical fixtures, publish side-by-side sha256 digests, re-verify every pass. Four passes of the CIScope rewrite produced identical digests each time — the proof is cheap and it survives review (PR #65, Sep 2026).

## Examples

```swift
enum SyncState: Sendable, Equatable {
    case idle
    case syncing(progress: Double?)
    case succeeded(Date)
    case failed(message: String)
}
```

Better than:

```swift
struct SyncState {
    var isLoading: Bool
    var error: String?
    var timestamp: Date?
}
```

## Switch hygiene

- Prefer exhaustive switches.
- Do not use `default` to silence important compiler feedback.
- For SDK/external/generated enums, only use unknown/default handling when forward compatibility truly requires it.

## Review questions

- Is this state actually finite?
- Would an enum make illegal states unrepresentable?
- Is the associated payload owned by the case or should it live elsewhere?
- Did `default` hide a real missed case?
