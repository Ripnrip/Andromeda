# Motion & Haptics

## iOS haptics

```swift
@MainActor
enum Haptic {
    case light, medium, success, warning, error

    func play() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        switch self {
        case .light: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error: UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}
```

**Fire on transitions** — not on loops or polls.

## macOS

```swift
NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
// .generic, .levelChange, .alignment
```

Trackpad-capable Macs only — visual feedback primary.

## Reduce Motion

| Setting | Behavior |
|---------|----------|
| `accessibilityReduceMotion` | disable shake/bounce/loop |
| `@AppStorage("reduceMotion")` | app-level override |

Static fallback: color, label, icon — never motion-only information.

## SF Symbols

```swift
Image(systemName: "arrow.triangle.2.circlepath")
    .symbolEffect(.rotate, isActive: isLoading)
```

## Sound

Off by default. `@AppStorage` gate. Never auto-play alerts.

## Domain mapping

Status → haptic/motion **tables** live in domain skills (e.g. anima-swift `fabric-status.md`). This doc is **how** to implement.
