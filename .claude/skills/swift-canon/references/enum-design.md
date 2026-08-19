# Enum Design

Enums are one of Swift's biggest strengths. Use them aggressively where state is finite and meaningful.

## Rules

- Prefer enums over loose strings/ints for state, mode, route, outcome, and lifecycle.
- Use associated values when payload belongs to the case.
- Keep the enum semantic: one case should mean one state.
- Avoid boolean pairs that imply hidden state matrices.
- **Derived strings (labels, IDs, descriptions) go through exhaustive `switch` — never `rawValue` concatenation or interpolation.** Runtime concatenation (`"memory." + rawValue`) means renaming a case silently drifts every derived string; a `switch self` is compiler-checked and fails loudly on new cases.
- **Call sites reference `.rawValue` — never re-type a literal an enum already owns.** Hand-typed literals drift from the enum silently (`hasPrefix("infer.write")` when the enum says `case inferWrite = "infer.write"`). If the string is a stable contract, the enum declaration is its single source of truth.
- Enforced by `canon/ast-grep/` rules in CI (`enum-raw-value-concat`, `bare-capability-literal`); see anti-patterns Exhibit 6.

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
