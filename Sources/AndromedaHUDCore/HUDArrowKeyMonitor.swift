import AppKit
import SwiftUI

/// Installs an AppKit local key monitor so ↑/↓ reach the HUD while a TextField is focused.
/// Zero-size `keyboardShortcut` Buttons are unreliable against the field editor.
struct HUDArrowKeyMonitor: NSViewRepresentable {
    var isActive: Bool
    var onUp: () -> Void
    var onDown: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isActive = isActive
        context.coordinator.onUp = onUp
        context.coordinator.onDown = onDown
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isActive: isActive, onUp: onUp, onDown: onDown)
    }

    final class Coordinator {
        var isActive: Bool
        var onUp: () -> Void
        var onDown: () -> Void
        private var monitor: Any?

        init(isActive: Bool, onUp: @escaping () -> Void, onDown: @escaping () -> Void) {
            self.isActive = isActive
            self.onUp = onUp
            self.onDown = onDown
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isActive else { return event }
                // Ignore key repeats with modifiers (keep Cmd/Opt/Shift chords for the system).
                guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
                    return event
                }
                switch event.keyCode {
                case 126: // ↑
                    self.onUp()
                    return nil
                case 125: // ↓
                    self.onDown()
                    return nil
                default:
                    return event
                }
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            uninstall()
        }
    }
}
