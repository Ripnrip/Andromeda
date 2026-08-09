#if os(macOS)
import SwiftUI
import AppKit

// MARK: - Floating control bar as a draggable LSUIElement panel
//
// The Andromeda floating strip is a menu-bar-class accessory: no Dock icon,
// no menu bar, floats above all spaces, and is dragged by its own body.
//
// 1. In Info.plist set `Application is agent (UIElement)` → YES
//    (LSUIElement = true) so the app has no Dock presence.
// 2. Use `AndromedaBarApp` below as the entry point, OR mount
//    `FloatingBarController` from an existing AppKit AppDelegate.

/// A non-activating, borderless, always-on-top panel that hosts SwiftUI and
/// is draggable anywhere on its surface.
@MainActor
public final class FloatingBarPanel: NSPanel {
    public init(content: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 72),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        isFloatingPanel = true
        level = .statusBar                       // above normal windows
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = true       // drag by the body
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false                        // SwiftUI draws the glass + shadow
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        hidesOnDeactivate = false
        contentView = content
    }

    // Borderless panels reject key focus by default — allow it for the search field.
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    /// Park the bar at the bottom-center of the active screen.
    public func centerBottom(margin: CGFloat = 40) {
        guard let screen = NSScreen.main else { return }
        let v = screen.visibleFrame
        setFrameOrigin(NSPoint(x: v.midX - frame.width / 2, y: v.minY + margin))
    }
}

/// Owns the panel + its SwiftUI content and shows it.
@MainActor
public final class FloatingBarController {
    public let panel: FloatingBarPanel
    public init<Content: View>(@ViewBuilder content: () -> Content) {
        let host = NSHostingView(rootView:
            content()
                .fixedSize()
                .background(Color.clear)
        )
        host.autoresizingMask = [.width, .height]
        panel = FloatingBarPanel(content: host)
        panel.setContentSize(host.fittingSize)
    }
    public func show() {
        panel.centerBottom()
        panel.orderFrontRegardless()             // show without activating the app
    }
    public func hide() { panel.orderOut(nil) }
}

/// A ready-made app entry point. Pair with LSUIElement = YES.
///
/// ```swift
/// @main struct Main: App {
///     @NSApplicationDelegateAdaptor(AndromedaBarDelegate.self) var delegate
///     var body: some Scene { Settings { EmptyView() } }   // no windows
/// }
/// ```
@MainActor
public final class AndromedaBarDelegate: NSObject, NSApplicationDelegate {
    var bar: FloatingBarController?
    public func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)    // LSUIElement behavior at runtime
        bar = FloatingBarController { AndromedaBarContent() }
        bar?.show()
    }
}

/// The SwiftUI content of the floating strip — the core, six capability
/// controls, and a live fleet pulse, in the Andromeda glass idiom.
public struct AndromedaBarContent: View {
    private let caps: [(String, String)] = [
        ("memory.recall", "brain.head.profile"),
        ("mcp.host", "point.3.connected.trianglepath.dotted"),
        ("skills.invoke", "sparkles"),
        ("infer.write", "square.and.pencil"),
        ("secrets.broker", "lock.shield"),
        ("fleet.pulse", "waveform.path.ecg"),
    ]
    @State private var beat = false
    public init() {}
    public var body: some View {
        HStack(spacing: 8) {
            AndromedaCore(size: 34)
            Divider().frame(height: 28).overlay(Color.andromedaTeal.opacity(0.15))
            ForEach(caps, id: \.0) { cap in
                VStack(spacing: 3) {
                    Image(systemName: cap.1).font(.system(size: 15))
                        .foregroundStyle(Color.andromedaGlow)
                    Text(cap.0.components(separatedBy: ".").first ?? "")
                        .font(.system(size: 8.5, design: .monospaced)).foregroundStyle(.secondary)
                }
                .frame(width: 52, height: 40)
                .contentShape(Rectangle())
            }
            Divider().frame(height: 28).overlay(Color.andromedaTeal.opacity(0.15))
            HStack(spacing: 6) {
                Circle().fill(Color.andromedaLive).frame(width: 8, height: 8)
                    .shadow(color: .andromedaLive, radius: beat ? 6 : 2)
                    .scaleEffect(beat ? 1.15 : 1)
                    .animation(.easeInOut(duration: 1.2).repeatForever(), value: beat)
                VStack(alignment: .leading, spacing: 0) {
                    Text("fleet · 3").font(.system(size: 11, weight: .medium, design: .monospaced))
                    Text("healthy").font(.system(size: 8.5, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(
                    LinearGradient(colors: [Color.andromedaTeal.opacity(0.55), .clear, .clear, Color.andromedaGlow.opacity(0.45)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 30, y: 18)
        )
        .foregroundStyle(Color.andromedaGlow)
        .onAppear { beat = true }
    }
}
#endif
