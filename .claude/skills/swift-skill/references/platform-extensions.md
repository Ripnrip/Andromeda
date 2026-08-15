# Platform Extensions

## App Intents

```swift
struct MyIntent: AppIntent {
    static var title: LocalizedStringResource = "Do Thing"
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await Service.shared.run()
        return .result(dialog: "Done")
    }
}
```

```swift
struct AppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: MyIntent(), phrases: ["Do thing in \(.applicationName)"])
    }
}
```

Parameterized: `@Parameter(title: "Query") var query: String`

**Domain intent list** → anima-swift `platform-surfaces.md`. API → here.

## TipKit

```swift
try? Tips.configure([.displayFrequency(.immediate)])

struct MyTip: Tip {
    var title: Text { Text("…") }
    var rules: [Rule] { [#Rule(Self.$shown) { !$0 }] }
    @Parameter static var shown: Bool = false
}

// view
.popoverTip(MyTip())
```

`Tips.MaxDisplayCount(1)` for one-shots. `Tips.showTipsForTesting(false)` in tests.

## WidgetKit

```swift
struct MyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "kind", provider: Provider()) { entry in
            WidgetView(entry: entry)
        }
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}
```

Timeline: `TimelineProvider` + `TimelineEntry`. Reload: `WidgetCenter.shared.reloadAllTimelines()` — throttle.

## Live Activities (ActivityKit)

```swift
struct MyAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable { … }
}
```

`Activity.request` / `Activity.update` / `Activity.end`. Dynamic Island: `dynamicIsland:` builder.

**Domain content model** → anima-swift `fabric-live-activity.md`.

## watchOS

- WidgetKit complications (`accessoryCircular`, `accessoryRectangular`)
- `WatchConnectivity` for phone → watch payload
- Glance `List` views — read-only on watch

## App Groups

`UserDefaults(suiteName:)` / shared container for extension ↔ app data.

## Control widgets (iOS 18+)

`.control` family + `AppIntent` button.
