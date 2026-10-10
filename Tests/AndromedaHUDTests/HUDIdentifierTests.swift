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

    private func expectHygienicIdentifiers(
        _ identifiers: Set<String>,
        excluding rawValues: [String] = []
    ) {
        for identifier in identifiers where identifier.hasPrefix("hud") {
            #expect(HUDIdentifier.recognizes(identifier), "unregistered identifier on glass: \(identifier)")
            for rawValue in rawValues where !rawValue.isEmpty {
                #expect(!identifier.contains(rawValue), "raw value leaked into identifier: \(rawValue)")
            }
        }
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
        let hits = [
            MemoryHit(contentHash: "content-alpha", narrative: "First private memory", source: .hotStore, score: 10.0),
            MemoryHit(contentHash: "content-beta", narrative: "Second private memory", project: "andromeda", source: .vault, score: 8.0),
        ]
        model.lastOutcome = .recalled(hits: hits)
        let found = identifiers(
            in: HUDView(isExpanded: true, searchQuery: "recall", model: model).padding(),
            frame: CGSize(width: 400, height: 320)
        )
        #expect(found.contains(HUDIdentifier.root.rawValue))
        #expect(found.contains(HUDIdentifier.resultsContainer.rawValue))
        expectHygienicIdentifiers(
            found,
            excluding: hits.flatMap { hit in
                [hit.id.uuidString.lowercased(), hit.contentHash ?? "", hit.narrative, hit.project ?? ""]
            }
        )
        for hit in hits {
            let identifier = HUDIdentifier.memoryHit(hit.id).rawValue
            #expect(found.contains(identifier))
            #expect(!identifier.contains(hit.id.uuidString.lowercased()))
            #expect(!identifier.contains(hit.narrative))
            if let project = hit.project {
                #expect(!identifier.contains(project))
            }
        }
    }

    @Test("recent queries carry list + per-item identifiers")
    func recentIdentifiers() {
        HUDModel.clearPersistedRecentQueries()
        let queries = ["project.state", "recall fleet observe"]
        let seeded = HUDModel(
            projectSurface: InMemoryProjectStateStore(),
            memorySessionReady: true,
            recentQueries: queries
        )
        let found = identifiers(
            in: HUDView(isExpanded: true, searchQuery: "", model: seeded).padding(),
            frame: CGSize(width: 400, height: 260)
        )
        #expect(found.contains(HUDIdentifier.resultsRecent.rawValue))
        expectHygienicIdentifiers(found, excluding: queries)
        for query in queries {
            let identifier = HUDIdentifier.recentQuery(query).rawValue
            #expect(found.contains(identifier))
            #expect(!identifier.contains(query))
        }
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
        expectHygienicIdentifiers(found, excluding: ["Memory store unavailable"])
    }

    @Test("project.state results carry pane + per-item identifiers")
    func projectIdentifiers() {
        let model = makeModel()
        let projectID: ProjectState.ID = "andromeda"
        let items = [
            ProjectStateItem(id: "HAB-838", title: "Private App Control UI", status: .active),
            ProjectStateItem(id: "HAB-557", title: "Private ticketing nudge", status: .backlog),
        ]
        model.lastOutcome = .projects(states: [
            ProjectState(
                id: projectID,
                title: "Andromeda",
                items: items
            ),
        ])
        let found = identifiers(
            in: HUDView(isExpanded: true, searchQuery: "project.state", model: model).padding(),
            frame: CGSize(width: 400, height: 320)
        )
        #expect(found.contains(HUDIdentifier.resultsContainer.rawValue))
        #expect(found.contains(HUDIdentifier.resultsProjects.rawValue))
        expectHygienicIdentifiers(
            found,
            excluding: ["andromeda", "Andromeda"] + items.flatMap { [$0.id.rawValue, $0.title] }
        )
        for item in items {
            let identifier = HUDIdentifier.projectItem(projectID: projectID, itemID: item.id).rawValue
            #expect(found.contains(identifier))
            #expect(!identifier.contains(item.id.rawValue))
            #expect(!identifier.contains(item.title))
        }
    }

    @Test("project item identifiers include project scope")
    func projectItemIdentifiersIncludeProjectScope() {
        let model = makeModel()
        let sharedItemID: ProjectStateItem.ID = "shared-item"
        let projects = [
            ProjectState(
                id: "project-alpha",
                title: "Private Alpha",
                items: [ProjectStateItem(id: sharedItemID, title: "Alpha task", status: .active)]
            ),
            ProjectState(
                id: "project-beta",
                title: "Private Beta",
                items: [ProjectStateItem(id: sharedItemID, title: "Beta task", status: .backlog)]
            ),
        ]
        model.lastOutcome = .projects(states: projects)

        let found = identifiers(
            in: HUDView(isExpanded: true, searchQuery: "project.state", model: model).padding(),
            frame: CGSize(width: 400, height: 360)
        )
        let expected = projects.map {
            HUDIdentifier.projectItem(projectID: $0.id, itemID: sharedItemID).rawValue
        }
        #expect(Set(expected).count == projects.count)
        for identifier in expected {
            #expect(found.contains(identifier))
        }
        expectHygienicIdentifiers(
            found,
            excluding: projects.flatMap { [$0.id.rawValue, $0.title] }
                + [sharedItemID.rawValue, "Alpha task", "Beta task"]
        )
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
        expectHygienicIdentifiers(found, excluding: ["Copied to clipboard"])
    }

    @Test("identifier scheme is dotted hud.* — no legacy camelCase survivors")
    func schemeHygiene() {
        let found = identifiers(
            in: HUDView(model: makeModel()).padding(),
            frame: CGSize(width: 400, height: 100)
        )
        // 📜 Static catalogue entries and opaque factory namespaces are the
        // whole law. Legacy spellings (hudResults.*), raw row content, and
        // rogue literals fail here.
        expectHygienicIdentifiers(found)
    }

    @Test("row identifier factories are stable, distinct, and opaque")
    func rowIdentifierFactoriesAreOpaque() throws {
        let queries = ["recall private launch narrative", "project.state private"]
        let recent = queries.map(HUDIdentifier.recentQuery)
        #expect(recent == queries.map(HUDIdentifier.recentQuery))
        #expect(Set(recent).count == queries.count)
        for (identifier, query) in zip(recent, queries) {
            #expect(!identifier.rawValue.contains(query))
            #expect(HUDIdentifier.recognizes(identifier.rawValue))
        }

        let firstID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let secondID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let hits = [
            MemoryHit(
                id: firstID,
                narrative: "Private memory narrative",
                project: "private-project",
                source: .hotStore,
                score: 1
            ),
            MemoryHit(
                id: secondID,
                narrative: "Another private narrative",
                project: "secret-project",
                source: .vault,
                score: 2
            ),
        ]
        let memory = hits.map { HUDIdentifier.memoryHit($0.id) }
        #expect(Set(memory).count == hits.count)
        for (identifier, hit) in zip(memory, hits) {
            #expect(identifier == HUDIdentifier.memoryHit(hit.id))
            #expect(!identifier.rawValue.contains(hit.id.uuidString.lowercased()))
            #expect(!identifier.rawValue.contains(hit.narrative))
            #expect(!identifier.rawValue.contains(hit.project ?? ""))
            #expect(HUDIdentifier.recognizes(identifier.rawValue))
        }

        let items = [
            ProjectStateItem(id: "HAB-838", title: "Private project title", status: .active),
            ProjectStateItem(id: "HAB-557", title: "Secret project title", status: .backlog),
        ]
        let projectID: ProjectState.ID = "private-project"
        let projects = items.map { HUDIdentifier.projectItem(projectID: projectID, itemID: $0.id) }
        #expect(Set(projects).count == items.count)
        for (identifier, item) in zip(projects, items) {
            #expect(identifier == HUDIdentifier.projectItem(projectID: projectID, itemID: item.id))
            #expect(!identifier.rawValue.contains(projectID.rawValue))
            #expect(!identifier.rawValue.contains(item.id.rawValue))
            #expect(!identifier.rawValue.contains(item.title))
            #expect(!identifier.rawValue.contains("HAB"))
            #expect(HUDIdentifier.recognizes(identifier.rawValue))
        }

        let reusedItemID: ProjectStateItem.ID = "shared-item"
        let firstScoped = HUDIdentifier.projectItem(projectID: "project-alpha", itemID: reusedItemID)
        let secondScoped = HUDIdentifier.projectItem(projectID: "project-beta", itemID: reusedItemID)
        #expect(firstScoped != secondScoped)

        #expect(Set(recent + memory + projects).count == recent.count + memory.count + projects.count)
        #expect(!HUDIdentifier.recognizes("hud.results.recent.item.raw-query"))
    }

    @Test("row identifiers survive source reordering")
    func rowIdentifiersSurviveReordering() throws {
        let queries = ["first private query", "second private query"]
        let rowsBefore = HUDRecentQueriesView.rows(for: queries)
        let rowsAfter = HUDRecentQueriesView.rows(for: Array(queries.reversed()))
        let identityBefore = Dictionary(uniqueKeysWithValues: rowsBefore.map { ($0.query, $0.id) })
        let identityAfter = Dictionary(uniqueKeysWithValues: rowsAfter.map { ($0.query, $0.id) })
        #expect(identityBefore == identityAfter)
        #expect(rowsBefore.map(\.id) != rowsAfter.map(\.id))

        let hitIDs = [
            try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333")),
            try #require(UUID(uuidString: "44444444-4444-4444-4444-444444444444")),
        ]
        let memoryIDs = hitIDs.map(HUDIdentifier.memoryHit)
        #expect(Array(memoryIDs.reversed()) == hitIDs.reversed().map(HUDIdentifier.memoryHit))

        let itemIDs: [ProjectStateItem.ID] = ["HAB-838", "HAB-557"]
        let projectID: ProjectState.ID = "andromeda"
        let projectIDs = itemIDs.map { HUDIdentifier.projectItem(projectID: projectID, itemID: $0) }
        #expect(
            Array(projectIDs.reversed())
                == itemIDs.reversed().map { HUDIdentifier.projectItem(projectID: projectID, itemID: $0) }
        )
    }

    @Test("memory row identifiers do not depend on narrative or ranking")
    func memoryRowIdentifiersIgnoreRankingInputs() throws {
        let hitID = try #require(UUID(uuidString: "55555555-5555-5555-5555-555555555555"))
        let quiet = MemoryHit(
            id: hitID,
            memoryID: UUID(uuidString: "66666666-6666-6666-6666-666666666666"),
            contentHash: "sha256:stable",
            narrative: "Quiet narrative",
            source: .hotStore,
            score: 0.5
        )
        // Same durable identity, different narrative/project/score/source.
        let loud = MemoryHit(
            id: hitID,
            memoryID: quiet.memoryID,
            contentHash: quiet.contentHash,
            narrative: "Totally different narrative",
            project: "some-project",
            source: .vault,
            score: 99
        )
        #expect(HUDIdentifier.memoryHit(quiet.id) == HUDIdentifier.memoryHit(loud.id))
        #expect(HUDIdentifier.memoryHit(hitID) != HUDIdentifier.memoryHit(UUID()))
    }
}
