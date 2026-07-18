#if canImport(AppKit)
import AppKit
import SwiftUI

/**
 Borderless, transparent `NSWindow` host for the floating HUD pill (BIN-60).

 Owns AppKit interop: non-activating panel, floating level, custom drag via
 the SwiftUI drag handle region, Pop-style velocity decay on release, and
 Ice-style menu-bar snap.
 */
@MainActor
public final class AndromedaHUDWindowController: NSObject {
    public let model: AndromedaHUDModel
    public private(set) var window: NSPanel
    private var hostingView: NSHostingView<AndromedaHUDView<EmptyView>>

    /// Event monitors are torn down in `deinit` (nonisolated), so they are stored unsafely.
    nonisolated(unsafe) private var mouseDownMonitor: Any?
    nonisolated(unsafe) private var mouseDraggedMonitor: Any?
    nonisolated(unsafe) private var mouseUpMonitor: Any?
    nonisolated(unsafe) private var dragStartOrigin: NSPoint?
    /// Rolling sample for Pop-style decay velocity (pts/s, AppKit y-up).
    nonisolated(unsafe) private var lastDragSample: (time: TimeInterval, origin: NSPoint)?
    nonisolated(unsafe) private var dragVelocity = CGVector(dx: 0, dy: 0)

    /// Builds a non-activating floating panel hosting `AndromedaHUDView`.
    public init(model: AndromedaHUDModel = AndromedaHUDModel()) {
        self.model = model
        let view = AndromedaHUDView(model: model, honorSystemReduceMotion: true)
        let hosting = NSHostingView(rootView: view)
        self.hostingView = hosting

        let size = NSSize(width: model.chromeSize.x, height: model.chromeSize.y)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentView = hosting
        self.window = panel
        super.init()

        if let screen = NSScreen.main {
            let metrics = Self.metrics(for: screen)
            model.dockToMenuBar(screen: metrics)
            applyModelFrame()
        }
        installDragMonitors()
    }

    deinit {
        if let mouseDownMonitor { NSEvent.removeMonitor(mouseDownMonitor) }
        if let mouseDraggedMonitor { NSEvent.removeMonitor(mouseDraggedMonitor) }
        if let mouseUpMonitor { NSEvent.removeMonitor(mouseUpMonitor) }
    }

    /// Show the HUD without activating the app.
    public func present() {
        applyModelFrame()
        window.orderFrontRegardless()
    }

    /// Hide the HUD.
    public func dismiss() {
        window.orderOut(nil)
    }

    /// Resize the panel to match collapsed / expanded chrome.
    public func applyModelFrame(animated: Bool = false) {
        let size = NSSize(width: model.chromeSize.x, height: model.chromeSize.y)
        var frame = window.frame
        // Keep top-left stable when expanding downward.
        let topY = frame.origin.y + frame.size.height
        frame.size = size
        frame.origin.y = topY - size.height
        if model.snapMode == .menuBar, let screen = window.screen ?? NSScreen.main {
            let metrics = Self.metrics(for: screen)
            frame.origin.x = model.origin.x
            frame.origin.y = metrics.menuBarDockY - size.height
            model.origin = HUDPoint(x: frame.origin.x, y: frame.origin.y)
        } else {
            frame.origin = NSPoint(x: model.origin.x, y: model.origin.y)
        }

        if animated, !model.reduceMotion {
            let spring = HUDPopMotion.snap
            NSAnimationContext.runAnimationGroup { context in
                context.duration = spring.response
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true
                window.animator().setFrame(frame, display: true)
            }
        } else {
            window.setFrame(frame, display: true)
        }
        hostingView.frame = NSRect(origin: .zero, size: size)
    }

    /// Convert an `NSScreen` into portable snap metrics.
    public static func metrics(for screen: NSScreen) -> HUDScreenMetrics {
        let visible = screen.visibleFrame
        let full = screen.frame
        let menuBarHeight = max(0, full.maxY - visible.maxY)
        return HUDScreenMetrics(
            visibleFrame: HUDRect(
                x: visible.origin.x,
                y: visible.origin.y,
                width: visible.size.width,
                height: visible.size.height
            ),
            menuBarHeight: menuBarHeight
        )
    }

    // MARK: - Drag (custom handle — not whole-window background)

    private func installDragMonitors() {
        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                if self.isEventInDragHandle(event) {
                    self.dragStartOrigin = self.window.frame.origin
                    self.lastDragSample = (ProcessInfo.processInfo.systemUptime, self.window.frame.origin)
                    self.dragVelocity = .zero
                }
            }
            return event
        }
        mouseDraggedMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                guard self.dragStartOrigin != nil else { return }
                var frame = self.window.frame
                frame.origin.x += event.deltaX
                // AppKit deltaY is flipped relative to increasing frame.origin.y.
                frame.origin.y -= event.deltaY
                self.window.setFrame(frame, display: true)
                self.sampleDragVelocity(at: frame.origin)
            }
            return event
        }
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                guard self.dragStartOrigin != nil else { return }
                self.dragStartOrigin = nil
                let screen = self.window.screen ?? NSScreen.main
                let metrics = screen.map(Self.metrics(for:)) ?? HUDScreenMetrics(
                    visibleFrame: HUDRect(x: 0, y: 0, width: 1440, height: 900)
                )
                let proposed = HUDPoint(x: self.window.frame.origin.x, y: self.window.frame.origin.y)
                let velocity = HUDPoint(x: self.dragVelocity.dx, y: self.dragVelocity.dy)
                self.model.endDrag(proposedOrigin: proposed, screen: metrics, velocity: velocity)
                self.applyModelFrame(animated: true)
                self.lastDragSample = nil
                self.dragVelocity = .zero
            }
            return event
        }
    }

    /// Estimate pts/s from successive drag samples for Pop decay.
    private func sampleDragVelocity(at origin: NSPoint) {
        let now = ProcessInfo.processInfo.systemUptime
        if let previous = lastDragSample {
            let dt = now - previous.time
            if dt > 0.001, dt < 0.12 {
                let vx = (origin.x - previous.origin.x) / dt
                let vy = (origin.y - previous.origin.y) / dt
                // Light EMA so a single jittery sample does not dominate decay.
                dragVelocity = CGVector(
                    dx: dragVelocity.dx * 0.35 + vx * 0.65,
                    dy: dragVelocity.dy * 0.35 + vy * 0.65
                )
            }
        }
        lastDragSample = (now, origin)
    }

    /// Hit-test the SwiftUI drag handle accessibility region approximately.
    private func isEventInDragHandle(_ event: NSEvent) -> Bool {
        guard event.window === window else { return false }
        let location = event.locationInWindow
        // Handle sits in the leading padding strip of the pill.
        let handleRect = NSRect(x: 8, y: window.frame.height - 42, width: 28, height: 32)
        return handleRect.contains(location)
    }
}
#else
// AppKit HUD window host is macOS-only. Portable model / snap / search compile everywhere.
#endif
