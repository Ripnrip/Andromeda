import AppKit
import ApplicationServices
import Darwin
import MemoryKit
import os
import SwiftUI
import Testing
@testable import AndromedaHUDCore

/// 🧪 Identifier coverage for the HUD glass (HAB-838 wave 1): the
/// `hud.<pane>.<control>` scheme must actually appear in the accessibility
/// tree — an identifier that compiles but never materializes is a lie the
/// App Control plane would repeat.
///
/// Walks the system AX tree (HIServices `AXUIElement`) rooted at our own
/// process: SwiftUI materializes hosted accessibility elements only when a
/// real AX client asks, so the walk queries the AX server from a background
/// thread while the main runloop pumps.
@Suite("Andromeda HUD Identifiers")
@MainActor
struct HUDIdentifierTests {
    // MARK: - AX tree walk

    /// 🌟 The system-tree walker — asks the AX *server* for our own element
    /// tree instead of poking AppKit's informal protocol. SwiftUI materializes
    /// hosted accessibility elements only for a real AX client, and an
    /// `AXUIElement` query is exactly that client (the same road XCUITest
    /// rides). In-process selector walks see only AppKit's layer.
    private struct AccessibilityWalk {
        var identifiers: Set<String> = []
        private(set) var visitedCount = 0
        var debugDump: [String] = []

        mutating func visit(_ element: AXUIElement, depth: Int = 0) {
            guard depth < 30 else { return }
            visitedCount += 1

            let identifier = Self.string(element, kAXIdentifierAttribute as CFString) ?? ""
            if !identifier.isEmpty {
                identifiers.insert(identifier)
            }
            if ProcessInfo.processInfo.environment["HUD_AX_DEBUG"] != nil {
                let role = Self.string(element, kAXRoleAttribute as CFString) ?? "?"
                let childCount = (Self.array(element, kAXChildrenAttribute as CFString) ?? []).count
                let description = Self.string(element, kAXDescriptionAttribute as CFString) ?? ""
                let size = Self.value(element, kAXSizeAttribute as CFString).map(Self.axSize) ?? .zero
                debugDump.append(
                    String(repeating: "  ", count: depth)
                        + "\(role) id='\(identifier)' desc='\(description)' "
                        + "size=\(Int(size.width))x\(Int(size.height)) children=\(childCount)"
                )
            }
            if let children = Self.array(element, kAXChildrenAttribute as CFString) {
                for child in children {
                    // Swift can't conditionally cast CF types — compare the
                    // type ID, then downcast with intent.
                    if let object = child as? AnyObject,
                       CFGetTypeID(object) == AXUIElementGetTypeID() {
                        visit(unsafeDowncast(object, to: AXUIElement.self), depth: depth + 1)
                    }
                }
            }
        }

        private static func string(_ element: AXUIElement, _ attribute: CFString) -> String? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
            return value as? String
        }

        private static func array(_ element: AXUIElement, _ attribute: CFString) -> [Any]? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
            return value as? [Any]
        }

        private static func value(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
            return value
        }

        /// 🎨 Unpacks an `AXValue` CGSize for the debug dump.
        private static func axSize(_ value: CFTypeRef) -> CGSize {
            guard CFGetTypeID(value) == AXValueGetTypeID() else { return .zero }
            var size = CGSize.zero
            AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgSize, &size)
            return size
        }
    }

    private func identifiers<Content: View>(in view: Content, frame: CGSize) -> Set<String> {
        // SwiftUI's AX bridge needs a live NSApplication to materialize
        // hosted accessibility elements — and the window server needs the
        // process to behave like a real app for its windows to register.
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: frame)
        hostingView.layoutSubtreeIfNeeded()

        // Realize the tree inside a titled window — borderless windows never
        // become key, and the AX server only reports windows it knows.
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        window.makeKeyAndOrderFront(nil)

        // 🎬 Complete the launch sequence and let the main loop turn a few
        // times — the app side of the AX IPC connection attaches to the main
        // runloop only once AppKit is actually running (querying earlier
        // dead-ends in kAXErrorNotImplemented).
        NSApp.finishLaunching()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        // 🌟 Query the system AX server for OUR OWN tree from a background
        // thread while the main runloop pumps — the AX connection is serviced
        // by the app's main loop, so querying it *from* the main thread
        // dead-ends in kAXErrorNotImplemented (-25208).
        let store = OSAllocatedUnfairLock(
            initialState: (identifiers: Set<String>(), visitedCount: 0, dump: [] as [String])
        )
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            let appElement = AXUIElementCreateApplication(getpid())
            var walk = AccessibilityWalk()
            walk.visit(appElement)
            let found = walk.identifiers
            let visitedCount = walk.visitedCount
            let dump = walk.debugDump
            store.withLock { $0 = (found, visitedCount, dump) }
            semaphore.signal()
        }
        let deadline = Date().addingTimeInterval(10)
        while semaphore.wait(timeout: .now()) == .timedOut && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        let (found, visitedCount, dump) = store.withLock { $0 }

        if found.isEmpty || ProcessInfo.processInfo.environment["HUD_AX_DEBUG"] != nil {
            print("🔍 AX walk diagnostics — visited \(visitedCount) nodes, identifiers \(found.sorted())")
            for line in dump {
                print("🌳 \(line)")
            }
        }
        window.orderOut(nil)
        return found
    }

    private func makeModel() -> HUDModel {
        HUDModel(
            projectSurface: InMemoryProjectStateStore(),
            memorySessionReady: true,
            recentQueries: []
        )
    }

    // MARK: - Coverage per state

    @Test("idle pill carries root, field, and fleet pulse identifiers")
    func idleIdentifiers() {
        // Hermetic model — a real window attachment runs `.task`, so the
        // model must not attempt an on-disk MemoryKit boot.
        let found = identifiers(
            in: HUDView(model: makeModel()).padding(),
            frame: CGSize(width: 400, height: 100)
        )
        #expect(found.contains(HUDIdentifier.root.rawValue))
        #expect(found.contains(HUDIdentifier.searchField.rawValue))
        #expect(found.contains(HUDIdentifier.fleetPulse.rawValue))
    }

    @Test("recalled outcome carries container + hit identifiers")
    func recalledIdentifiers() {
        let model = makeModel()
        model.lastOutcome = .recalled(hits: [
            MemoryHit(narrative: "First memory", source: .hotStore, score: 10.0),
            MemoryHit(narrative: "Second memory", project: "andromeda", source: .vault, score: 8.0),
        ])
        let found = identifiers(
            in: HUDView(isExpanded: true, searchQuery: "recall", model: model).padding(),
            frame: CGSize(width: 400, height: 320)
        )
        #expect(found.contains(HUDIdentifier.root.rawValue))
        #expect(found.contains(HUDIdentifier.resultsContainer.rawValue))
        #expect(found.contains(HUDIdentifier.resultsHit.rawValue))
    }

    @Test("recent queries carry list + per-item identifiers")
    func recentIdentifiers() {
        HUDModel.clearPersistedRecentQueries()
        let seeded = HUDModel(
            projectSurface: InMemoryProjectStateStore(),
            memorySessionReady: true,
            recentQueries: ["project.state", "recall fleet observe"]
        )
        let found = identifiers(
            in: HUDView(isExpanded: true, searchQuery: "", model: seeded).padding(),
            frame: CGSize(width: 400, height: 260)
        )
        #expect(found.contains(HUDIdentifier.resultsRecent.rawValue))
        #expect(found.contains(HUDIdentifier.resultsRecentItem.rawValue))
    }

    @Test("failed outcome carries the status row identifier")
    func statusIdentifiers() {
        let model = makeModel()
        model.lastOutcome = .failed(message: "Memory store unavailable")
        let found = identifiers(
            in: HUDView(isExpanded: true, searchQuery: "recall", model: model).padding(),
            frame: CGSize(width: 400, height: 200)
        )
        #expect(found.contains(HUDIdentifier.resultsContainer.rawValue))
        #expect(found.contains(HUDIdentifier.resultsStatus.rawValue))
    }

    @Test("project.state results carry pane + per-item identifiers")
    func projectIdentifiers() {
        let model = makeModel()
        model.lastOutcome = .projects(states: [
            ProjectState(
                id: "andromeda",
                title: "Andromeda",
                items: [
                    ProjectStateItem(id: "hab-838", title: "App Control UI", status: .active),
                    ProjectStateItem(id: "hab-557", title: "Ticketing nudge", status: .backlog),
                ]
            ),
        ])
        let found = identifiers(
            in: HUDView(isExpanded: true, searchQuery: "project.state", model: model).padding(),
            frame: CGSize(width: 400, height: 320)
        )
        #expect(found.contains(HUDIdentifier.resultsContainer.rawValue))
        #expect(found.contains(HUDIdentifier.resultsProjects.rawValue))
        #expect(found.contains(HUDIdentifier.resultsProjectsItem.rawValue))
    }

    @Test("activation feedback carries its identifier")
    func feedbackIdentifiers() {
        let model = makeModel()
        model.activationFeedback = "Copied to clipboard"
        let found = identifiers(
            in: HUDView(isExpanded: true, searchQuery: "recall", model: model).padding(),
            frame: CGSize(width: 400, height: 200)
        )
        #expect(found.contains(HUDIdentifier.feedback.rawValue))
    }

    @Test("identifier scheme is dotted hud.* — no legacy camelCase survivors")
    func schemeHygiene() {
        let found = identifiers(
            in: HUDView(model: makeModel()).padding(),
            frame: CGSize(width: 400, height: 100)
        )
        // 📜 The catalogue is the whole law: every hud-prefixed identifier on
        // glass must be a member — legacy spellings (hudResults.*) and rogue
        // literals fail here by construction, because the enum is the only
        // way views can stamp one.
        let catalogue = Set(HUDIdentifier.allCases.map(\.rawValue))
        for identifier in found where identifier.hasPrefix("hud") {
            #expect(catalogue.contains(identifier), "unregistered identifier on glass: \(identifier)")
        }
    }
}
