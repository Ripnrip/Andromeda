# Enum Design

Enums are one of Swift's biggest strengths. Use them aggressively where state is finite and meaningful.

## Rules

- Prefer enums over loose strings/ints for state, mode, route, outcome, and lifecycle.
- Use associated values when payload belongs to the case.
- Keep the enum semantic: one case should mean one state.
- Avoid boolean pairs that imply hidden state matrices.

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
