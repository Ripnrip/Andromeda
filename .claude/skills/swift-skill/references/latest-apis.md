# Latest APIs — Migration Quick Reference

Check deployment target before adopting. Replace deprecated patterns in refactors.

## High-impact migrations

| Deprecated | Modern |
|------------|--------|
| `onChange(of:) { v in }` single param | `onChange(of:) { old, new in }` |
| `.animation(.default)` no value | `.animation(_:value:)` |
| `NavigationView` | `NavigationStack` |
| `foregroundColor` | `foregroundStyle` |
| `cornerRadius(_:)` alone | `clipShape(.rect(cornerRadius:))` |
| `ObservableObject` + `@Published` (new code) | `@Observable` |
| `Task.sleep(nanoseconds:)` | `Task.sleep(for: .seconds(n))` |
| `fontWeight(.bold)` on fonts | `.bold()` on `Font` |

## SwiftUI state (iOS 17+)

- `@Observable` + `@State` for owned reference models
- `@Bindable` for injected observables needing bindings

## Concurrency

- Swift 6 strict mode
- `@Sendable` closures in async contexts

## Platform

- ActivityKit for Live Activities
- App Intents over legacy SiriKit for new shortcuts
- `symbolEffect` for animated SF Symbols

When unsure, prefer Apple sample code for current SDK year.
