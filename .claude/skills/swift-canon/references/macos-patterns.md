# macOS Patterns

## MenuBarExtra

```swift
@main
struct App: App {
    var body: some Scene {
        MenuBarExtra("App", systemImage: "star") {
            MenuContent()
        }
        .menuBarExtraStyle(.window)  // larger popover
    }
}
```

## Floating window

```swift
Window("Panel", id: "panel") {
    ContentView()
        .background(.clear)
}
.windowStyle(.plain)
```

`NSWindow.Level.floating` via `WindowGroup` + host configuration when borderless drag needed.

### Always-on-top companion HUD (NSPanel) [ML — proven in Morphling]

For floating overlays that ride above ALL windows/spaces (companion HUDs,
pets, status orbs) — plain `Window` style is not enough; use an `NSPanel`:

```swift
let panel = NSPanel(
    contentRect: .init(x: 0, y: 0, width: 340, height: 420),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered, defer: false
)
panel.isFloatingPanel = true
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
panel.isOpaque = false
panel.backgroundColor = .clear
panel.setContentView(NSHostingView(rootView: CompanionView()))
panel.orderFrontRegardless()
```

Key properties: `.nonactivatingPanel` (clicks don't steal app focus),
`.canJoinAllSpaces + .stationary` (visible on every Space, doesn't move on
mission-control), clear + non-opaque for shaped/transparent SwiftUI content.
The hosted SwiftUI view can then morph shape/size freely (see
`animations.md` → Shape morphing) — the panel just needs a frame big enough
to contain the largest form.

## NSStatusItem (custom)

When `MenuBarExtra` insufficient (custom drawn icon, badge):

```swift
let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
let hosting = NSHostingView(rootView: StatusLabel())
item.button?.addSubview(hosting)
```

Prefer `MenuBarExtra` first — see anima `ui-surfaces.md` for product choice.

## Keyboard

```swift
.focusable()
.onKeyPress(.space) { handle(); return .handled }
```

## File watching

`DispatchSourceFileSystemObject` on directory/file — hop to `@MainActor` in handler.

## Drag

Draggable chrome: `WindowDragGesture` or AppKit `mouseDownCanMoveWindow` on hosting view.

## Reduce Motion

`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`
