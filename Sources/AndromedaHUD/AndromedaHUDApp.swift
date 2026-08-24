import AppKit
import SwiftUI
import Carbon
import AndromedaHUDCore

@main
struct AndromedaHUDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // We do not use WindowGroup to avoid standard macOS window decorations and behaviors.
        // The AppDelegate manages the HUD window directly.
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var hudWindow: HUDWindow?
    var overlayWindow: HUDOverlayWindow?
    private var statusItem: NSStatusItem?
    private var eventMonitor: Any?

    private enum Prefs {
        static let originX = "andromeda.hud.originX"
        static let originY = "andromeda.hud.originY"
        static let userMoved = "andromeda.hud.userMoved"
        static let screenID = "andromeda.hud.screenID"
        static let alwaysOnTop = "andromeda.hud.alwaysOnTop"
    }

    /// True once the user has freely dragged the HUD away from menu-bar snap.
    private var userHasRepositioned: Bool {
        get { UserDefaults.standard.bool(forKey: Prefs.userMoved) }
        set { UserDefaults.standard.set(newValue, forKey: Prefs.userMoved) }
    }

    /// Floating (always-on-top) vs statusBar level.
    private var alwaysOnTop: Bool {
        get {
            if UserDefaults.standard.object(forKey: Prefs.alwaysOnTop) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Prefs.alwaysOnTop)
        }
        set { UserDefaults.standard.set(newValue, forKey: Prefs.alwaysOnTop) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory = no Dock icon; floating HUD panel stays above normal windows.
        NSApp.setActivationPolicy(.accessory)

        setupHUDWindow()
        setupStatusItem()
        setupGlobalHotkey()
        setupScreenObservers()
        setupResignKeyObserver()
        setupClickOutsideMonitor()
        setupHUDNotifications()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    // MARK: - Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Andromeda HUD")
            button.toolTip = "Andromeda HUD — click to show"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        refreshStatusItemAttention()
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            toggleHUDVisibility()
            return
        }
        if event.type == .rightMouseUp {
            showStatusMenu()
        } else {
            // Left click: open / focus HUD
            showHUD()
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()

        let show = NSMenuItem(title: "Show HUD", action: #selector(menuShowHUD), keyEquivalent: "")
        show.target = self
        menu.addItem(show)

        let snap = NSMenuItem(
            title: "Snap to Menu Bar",
            action: #selector(menuSnapToMenuBar),
            keyEquivalent: "m"
        )
        snap.keyEquivalentModifierMask = [.command, .shift]
        snap.target = self
        menu.addItem(snap)

        let levelTitle = alwaysOnTop ? "Window Level: Floating ✓" : "Window Level: Status"
        let level = NSMenuItem(title: levelTitle, action: #selector(menuToggleWindowLevel), keyEquivalent: "")
        level.target = self
        menu.addItem(level)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Andromeda HUD", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        // Clear menu after display so left-click stays a simple show action.
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.menu = nil
        }
    }

    @objc private func menuShowHUD() {
        showHUD()
    }

    @objc private func menuSnapToMenuBar() {
        snapToMenuBarExplicitly()
        showHUD()
    }

    @objc private func menuToggleWindowLevel() {
        alwaysOnTop.toggle()
        applyWindowLevel()
        refreshStatusItemAttention()
    }

    private func refreshStatusItemAttention() {
        guard let button = statusItem?.button else { return }
        // Subtle attention: filled vs outline when always-on-top.
        let name = alwaysOnTop ? "sparkles" : "sparkle"
        button.image = NSImage(systemSymbolName: name, accessibilityDescription: "Andromeda HUD")
    }

    // MARK: - Window

    private func setupScreenObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func setupResignKeyObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hudDidResignKey(_:)),
            name: NSWindow.didResignKeyNotification,
            object: nil
        )
    }

    private func setupClickOutsideMonitor() {
        // Hide HUD when clicking outside of it.
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let window = self.hudWindow, window.isVisible else { return }
            let loc = NSEvent.mouseLocation
            if !window.frame.contains(loc) {
                NotificationCenter.default.post(name: .andromedaHUDCollapseResults, object: nil)
                window.orderOut(nil)
                self.overlayWindow?.orderOut(nil)
                self.overlayWindow = nil
            }
        }
    }

    private func setupHUDNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(requestHide(_:)),
            name: .andromedaHUDRequestHide,
            object: nil
        )
    }

    @objc private func hudDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === hudWindow else { return }
        NotificationCenter.default.post(name: .andromedaHUDCollapseResults, object: nil)
    }

    @objc private func requestHide(_ notification: Notification) {
        hudWindow?.orderOut(nil)
    }

    func setupHUDWindow() {
        let hostingView = AutoSizingHostingView(rootView: HUDView())
        hostingView.sizingOptions = [.intrinsicContentSize]

        let window = HUDWindow(
            contentRect: NSRect(x: 0, y: 0, width: 250, height: 50),
            // Borderless key panel — allow click-to-focus the TextField.
            // Do not use .nonactivatingPanel: it blocks first-responder and keeps the pill idle-width.
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hasShadow = false

        self.hudWindow = window
        applyWindowLevel()

        // First launch: snap under menu bar. Subsequent launches: restore last screen + origin.
        if userHasRepositioned, let saved = persistedOrigin() {
            restoreToScreen(origin: saved)
        } else {
            snapToMenuBar()
        }

        window.makeKeyAndOrderFront(nil)
        hostingView.resizeWindowToFitContent(anchorTop: true)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDidDragWindow(_:)),
            name: .andromedaHUDUserDidDragWindow,
            object: nil
        )
    }

    private func applyWindowLevel() {
        guard let window = hudWindow else { return }
        window.level = alwaysOnTop ? .floating : .statusBar
    }

    @objc private func userDidDragWindow(_ notification: Notification) {
        noteUserFinishedDrag()
    }

    /// Called after `performDrag` returns (mouse up) — not on programmatic size/origin changes.
    func noteUserFinishedDrag() {
        guard let window = hudWindow else { return }
        userHasRepositioned = true
        persistOrigin(window.frame.origin)
        persistScreen(for: window)
    }

    func showHUD() {
        guard let window = hudWindow else { return }
        
        // Show overlay
        if overlayWindow == nil {
            overlayWindow = HUDOverlayWindow()
        }
        if let screen = preferredScreen() ?? screenUnderMouse() ?? NSScreen.main {
            overlayWindow?.setFrame(screen.frame, display: true)
        }
        overlayWindow?.makeKeyAndOrderFront(nil)
        
        if userHasRepositioned, let saved = persistedOrigin() {
            restoreToScreen(origin: saved)
        } else {
            snapToMenuBar()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let hosting = window.contentView as? AutoSizingHostingView<HUDView> {
            hosting.resizeWindowToFitContent(anchorTop: true)
        }
        // Expand + focus search after the panel is key.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .andromedaHUDFocusSearch, object: nil)
        }
    }

    func toggleHUDVisibility() {
        guard let window = hudWindow else { return }
        if window.isVisible {
            window.orderOut(nil)
            overlayWindow?.orderOut(nil)
            overlayWindow = nil
        } else {
            showHUD()
        }
    }

    /// Deliberate snap path (menu / ⌘⇧M). Clears free-drag preference.
    func snapToMenuBarExplicitly() {
        userHasRepositioned = false
        UserDefaults.standard.removeObject(forKey: Prefs.originX)
        UserDefaults.standard.removeObject(forKey: Prefs.originY)
        UserDefaults.standard.removeObject(forKey: Prefs.screenID)
        snapToMenuBar()
        if let window = hudWindow {
            persistScreen(for: window)
        }
    }

    func setupGlobalHotkey() {
        // Cmd+Shift+Space — toggle HUD
        registerHotKey(id: 1, keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
            self?.toggleHUDVisibility()
        }
        // Cmd+Shift+M — snap to menu bar
        registerHotKey(id: 2, keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
            self?.snapToMenuBarExplicitly()
            self?.showHUD()
        }
    }

    private var hotKeyHandlers: [UInt32: () -> Void] = [:]

    private func registerHotKey(id: UInt32, keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        hotKeyHandlers[id] = handler

        var hotKeyRef: EventHotKeyRef?
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(fourCharCode: "AHUD")
        hotKeyID.id = id

        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        // Install handler once.
        if id == 1 {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )

            let appDelegatePtr = Unmanaged.passUnretained(self).toOpaque()

            let carbonHandler: EventHandlerUPP = { (_, event, userData) -> OSStatus in
                guard let userData, let event else { return noErr }
                var hkID = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                guard err == noErr else { return noErr }

                let bitPattern = UInt(bitPattern: userData)
                let hotKeyID = hkID.id
                DispatchQueue.main.async {
                    guard let ptr = UnsafeMutableRawPointer(bitPattern: bitPattern) else { return }
                    let appDelegate = Unmanaged<AppDelegate>.fromOpaque(ptr).takeUnretainedValue()
                    appDelegate.hotKeyHandlers[hotKeyID]?()
                }
                return noErr
            }

            InstallEventHandler(
                GetApplicationEventTarget(),
                carbonHandler,
                1,
                &eventType,
                appDelegatePtr,
                nil
            )
        }
    }

    @objc func screenParametersDidChange() {
        ensureOnVisibleScreen()
    }

    /// If the HUD drifted off every screen (display unplug), nudge it onto a visible frame.
    func ensureOnVisibleScreen() {
        guard let window = hudWindow else { return }
        let frame = window.frame
        let intersectsAny = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
        guard !intersectsAny else { return }

        if userHasRepositioned {
            let screen = preferredScreen() ?? screenUnderMouse() ?? NSScreen.main ?? NSScreen.screens.first
            guard let activeScreen = screen else { return }
            let vf = activeScreen.visibleFrame
            let origin = NSPoint(
                x: vf.midX - frame.width / 2,
                y: min(max(frame.origin.y, vf.minY), vf.maxY - frame.height - 10)
            )
            window.setFrameOrigin(origin)
            persistOrigin(origin)
            persistScreen(for: window)
        } else {
            snapToMenuBar()
        }
    }

    func snapToMenuBar() {
        guard let window = hudWindow else { return }
        let activeScreen = preferredScreen() ?? screenUnderMouse() ?? NSScreen.main ?? NSScreen.screens.first
        guard let activeScreen else { return }

        let screenFrame = activeScreen.visibleFrame
        let windowFrame = window.frame
        let x = screenFrame.midX - (windowFrame.width / 2)
        let y = screenFrame.maxY - windowFrame.height - 10
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func restoreToScreen(origin: NSPoint) {
        guard let window = hudWindow else { return }
        if let screen = preferredScreen() {
            // Clamp saved origin into the preferred screen's visible frame.
            let vf = screen.visibleFrame
            let clamped = NSPoint(
                x: min(max(origin.x, vf.minX), vf.maxX - window.frame.width),
                y: min(max(origin.y, vf.minY), vf.maxY - window.frame.height)
            )
            window.setFrameOrigin(clamped)
        } else {
            window.setFrameOrigin(origin)
        }
    }

    private func screenUnderMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
    }

    private func preferredScreen() -> NSScreen? {
        let savedID = UserDefaults.standard.string(forKey: Prefs.screenID)
        if let savedID {
            if let match = NSScreen.screens.first(where: { $0.hudScreenID == savedID }) {
                return match
            }
        }
        return nil
    }

    private func persistOrigin(_ origin: NSPoint) {
        UserDefaults.standard.set(Double(origin.x), forKey: Prefs.originX)
        UserDefaults.standard.set(Double(origin.y), forKey: Prefs.originY)
    }

    private func persistScreen(for window: NSWindow) {
        if let screen = window.screen ?? screenUnderMouse() {
            UserDefaults.standard.set(screen.hudScreenID, forKey: Prefs.screenID)
        }
    }

    private func persistedOrigin() -> NSPoint? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Prefs.originX) != nil,
              defaults.object(forKey: Prefs.originY) != nil else {
            return nil
        }
        return NSPoint(
            x: defaults.double(forKey: Prefs.originX),
            y: defaults.double(forKey: Prefs.originY)
        )
    }
}

private extension NSScreen {
    /// Stable-enough screen key for UserDefaults restore (display ID when available).
    var hudScreenID: String {
        if let num = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return "display-\(num.uint32Value)"
        }
        return localizedName
    }
}

/// NSHostingView that grows/shrinks the borderless HUD panel with SwiftUI intrinsic size.
/// Keeps the **top** edge fixed so results expand downward under the pill.
final class AutoSizingHostingView<Content: View>: NSHostingView<Content> {
    private var lastFittedSize: NSSize = .zero

    override func layout() {
        super.layout()
        resizeWindowToFitContent(anchorTop: true)
    }

    func resizeWindowToFitContent(anchorTop: Bool) {
        guard let window else { return }
        invalidateIntrinsicContentSize()
        var fitted = fittingSize
        fitted.width = max(fitted.width, 160)
        fitted.height = max(fitted.height, 44)

        if abs(fitted.width - lastFittedSize.width) < 0.5,
           abs(fitted.height - lastFittedSize.height) < 0.5 {
            return
        }
        lastFittedSize = fitted

        var frame = window.frame
        let oldMaxY = frame.maxY
        frame.size = fitted
        if anchorTop {
            frame.origin.y = oldMaxY - fitted.height
        }
        window.setFrame(frame, display: true)
    }
}

class HUDWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Become key before hit-testing so the SwiftUI TextField can take first responder.
    /// Dragging is handled only by `WindowDragNSView` (drag handle) — never
    /// `performDrag` on the panel itself (that turned every click into a drag).
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            if !isKeyWindow {
                makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        super.sendEvent(event)
    }
}

extension OSType {
    init(fourCharCode: String) {
        var result: OSType = 0
        if let data = fourCharCode.data(using: .macOSRoman) {
            for (index, byte) in data.enumerated() {
                result = result | (OSType(byte) << (24 - index * 8))
            }
        }
        self = result
    }
}
