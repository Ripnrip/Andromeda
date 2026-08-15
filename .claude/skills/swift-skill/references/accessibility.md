# Accessibility

## Controls

- **`Button`** over `onTapGesture` — free VoiceOver + keyboard
- `accessibilityLabel` when default label unclear
- `accessibilityHint` for non-obvious outcomes
- `accessibilityAddTraits(.isButton)` on custom tappables

## Grouping

```swift
.accessibilityElement(children: .combine)
```

Join related text for single swipe stop.

## Dynamic Type

```swift
@ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 8
```

Never fixed `.font(.system(size: 12))` for body content.

## Custom controls

```swift
.accessibilityRepresentation {
    Button("…") { action() }
}
```

## Announcements

```swift
AccessibilityNotification.Announcement("Status changed").post()
```

On meaningful **transitions** — not every refresh.

## Reduce Motion

Respect `accessibilityReduceMotion` — see `motion-haptics.md`.

## Previews

```swift
#Preview {
    MyView()
        .environment(\.dynamicTypeSize, .accessibility3)
}
```

## Testing

VoiceOver rotor navigation + Dynamic Type XXL in manual QA; snapshot at `.accessibility3` optional.

## Domain copy

Spoken strings for product-specific states → domain skill. Patterns → here.
