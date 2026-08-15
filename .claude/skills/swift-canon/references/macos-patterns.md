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
