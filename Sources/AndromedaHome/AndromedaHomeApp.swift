import SwiftUI
import AppKit
import AndromedaHomeCore

/// 🎭 AndromedaHomeApp — visible product home for the Andromeda control plane.
///
/// Ships a real macOS window (not a Python CLI). Default path is memory.*
/// (store / recall / journal) via MemoryKit Capture + Retrieval. MultibrainBar
/// / FleetObserveBar stay the day-to-day menu-bar tools.
@main
struct AndromedaHomeApp: App {
    @NSApplicationDelegateAdaptor(AndromedaAppDelegate.self) private var appDelegate
    @State private var model = AndromedaHomeModel()

    var body: some Scene {
        WindowGroup("Andromeda") {
            AndromedaHomeView(model: model)
                .frame(minWidth: 720, minHeight: 520)
                .task { await model.bootstrap() }
        }
        .defaultSize(width: 780, height: 640)
    }
}

final class AndromedaAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        print("🌐 ✨ ANDROMEDA HOME AWAKENS — memory.* product shell")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
