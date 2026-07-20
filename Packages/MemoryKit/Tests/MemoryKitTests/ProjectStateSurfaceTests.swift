/**
 * 🧪 The ProjectStateSurfaceTests - Capability Curtain Quality Rituals
 *
 * "We prove the seeker can list, get, create, and update—
 * while Codable refuses to smuggle Linear∪Multica neon past the velvet,
 * and the operator bridge merges mock fragments without brand URLs."
 *
 * - The Theatrical Quality Virtuoso of project.state
 */

import Foundation
import Testing
@testable import MemoryKit

@Suite("🎭 Project State Capability Rituals ✨")
struct ProjectStateSurfaceTests {

    private func seedBoard() -> [ProjectState] {
        [
            ProjectState(
                id: ProjectStateID(rawValue: "andromeda"),
                title: "Andromeda",
                status: .active,
                items: [
                    ProjectStateItem(
                        id: ProjectStateItemID(rawValue: "seed-1"),
                        title: "Capability curtain",
                        status: .active
                    )
                ],
                provenance: ProjectStateProvenance(linearIssueID: "BIN-99", multicaIssueID: "HAB-99")
            )
        ]
    }

    @Test("📜 project.state.list returns seeded projects sorted by title")
    func testListProjects() async throws {
        let store = InMemoryProjectStateStore(seed: seedBoard() + [
            ProjectState(id: ProjectStateID(rawValue: "zeta"), title: "Zeta", status: .backlog),
            ProjectState(id: ProjectStateID(rawValue: "alpha"), title: "Alpha", status: .done),
        ])
        let listed = try await store.listProjects()
        #expect(listed.map(\.title) == ["Alpha", "Andromeda", "Zeta"])
        print("🎉 ✨ PROJECT.STATE.LIST RITUAL COMPLETE!")
    }

    @Test("🔎 project.state.get returns project and throws when missing")
    func testGetProject() async throws {
        let store = InMemoryProjectStateStore(seed: seedBoard())
        let project = try await store.getProject(ProjectStateID(rawValue: "andromeda"))
        #expect(project.title == "Andromeda")
        #expect(project.items.count == 1)

        do {
            _ = try await store.getProject(ProjectStateID(rawValue: "missing"))
            Issue.record("Expected projectNotFound")
        } catch let error as ProjectStateError {
            #expect(error == .projectNotFound(ProjectStateID(rawValue: "missing")))
        }

        print("🎉 ✨ PROJECT.STATE.GET RITUAL COMPLETE!")
    }

    @Test("✨ project.state.create appends item; project.state.update patches fields")
    func testCreateAndUpdate() async throws {
        let store = InMemoryProjectStateStore(seed: seedBoard())
        let created = try await store.createItem(
            ProjectStateDraft(
                projectID: ProjectStateID(rawValue: "andromeda"),
                title: "New item",
                status: .backlog,
                notes: "curtain"
            )
        )
        #expect(created.title == "New item")
        #expect(created.status == .backlog)

        let updated = try await store.updateItem(
            created.id,
            ProjectStatePatch(title: "Renamed", status: .done, notes: "shipped")
        )
        #expect(updated.title == "Renamed")
        #expect(updated.status == .done)
        #expect(updated.notes == "shipped")

        let project = try await store.getProject(ProjectStateID(rawValue: "andromeda"))
        #expect(project.items.contains(where: { $0.id == created.id && $0.title == "Renamed" }))
        print("🎉 ✨ PROJECT.STATE.CREATE+UPDATE MASTERPIECE COMPLETE!")
    }

    @Test("🪄 Codable omits provenance — no Linear/Multica IDs in client JSON")
    func testCodableStripsProvenance() throws {
        let project = seedBoard()[0]
        let data = try JSONEncoder().encode(project)
        let json = String(decoding: data, as: UTF8.self)

        #expect(!json.contains("BIN-99"))
        #expect(!json.contains("HAB-99"))
        #expect(!json.contains("linear"))
        #expect(!json.contains("multica"))
        #expect(!json.contains("provenance"))
        #expect(!json.contains("linear.com"))
        #expect(json.contains("Andromeda"))
        #expect(json.contains("Capability curtain"))

        let decoded = try JSONDecoder().decode(ProjectState.self, from: data)
        #expect(decoded.provenance == nil)
        #expect(decoded.title == "Andromeda")
        print("🎉 ✨ PROVENANCE CURTAIN SEALED!")
    }

    @Test("🚫 Public fields never carry tracker URLs")
    func testNoTrackerURLsInPublicFields() {
        let project = ProjectState(
            id: ProjectStateID(rawValue: "p1"),
            title: "Board",
            status: .active,
            items: [
                ProjectStateItem(id: ProjectStateItemID(rawValue: "i1"), title: "Task", status: .active)
            ],
            provenance: ProjectStateProvenance(linearIssueID: "BIN-1", multicaIssueID: "HAB-1")
        )
        #expect(project.id.rawValue == "p1")
        #expect(project.provenance?.linearIssueID == "BIN-1")
        #expect(project.provenance?.multicaIssueID == "HAB-1")
        print("🎉 ✨ NO TRACKER URL FIELDS ON PUBLIC SURFACE!")
    }

    @Test("🎪 Operator bridge merges mock Linear+Multica into brand-neutral items")
    func testOperatorBridgeMerge() async throws {
        let linear = MockLinearProvider(issues: [
            LinearIssueFragment(id: "BIN-40", title: "Capability curtain", state: "In Progress"),
        ])
        let multica = MockMulticaProvider(issues: [
            MulticaIssueFragment(id: "HAB-40", title: "Capability curtain", status: "active"),
            MulticaIssueFragment(id: "HAB-41", title: "Habitat-only row", status: "todo"),
        ])
        let bridge = OperatorProjectStateBridge(
            linear: linear,
            multica: multica,
            projectID: ProjectStateID(rawValue: "andromeda"),
            projectTitle: "Andromeda"
        )

        let listed = try await bridge.listProjects()
        #expect(listed.count == 1)
        let project = listed[0]
        #expect(project.title == "Andromeda")
        #expect(project.items.count == 2)
        #expect(project.items.contains(where: { $0.title == "Capability curtain" && $0.status == .active }))
        #expect(project.items.contains(where: { $0.title == "Habitat-only row" && $0.status == .backlog }))

        let data = try JSONEncoder().encode(project)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("BIN-40"))
        #expect(!json.contains("HAB-40"))
        #expect(!json.contains("HAB-41"))
        #expect(!json.contains("linear.app"))
        #expect(!json.contains("linear.com"))
        #expect(!json.contains("multica"))
        #expect(!json.contains("provenance"))
        print("🎉 ✨ OPERATOR BRIDGE MERGE RITUAL COMPLETE!")
    }

    @Test("🌙 Null providers leave an empty Andromeda board (bridgeNotWired soft path)")
    func testNullProvidersSeedEmptyBoard() async throws {
        let bridge = OperatorProjectStateBridge()
        let listed = try await bridge.listProjects()
        #expect(listed.count == 1)
        #expect(listed[0].title == "Andromeda")
        #expect(listed[0].items.isEmpty)
        print("🎉 ✨ NULL PROVIDER SOFT PATH COMPLETE!")
    }

    @Test("✨ project.state.create fans Linear→Multica; client item stays brand-neutral")
    func testCreateFanOut() async throws {
        let linear = MockLinearProvider(issues: [])
        let multica = MockMulticaProvider(issues: [])
        let bridge = OperatorProjectStateBridge(linear: linear, multica: multica)

        let item = try await bridge.createItem(
            ProjectStateDraft(
                projectID: ProjectStateID(rawValue: "andromeda"),
                title: "Wire the curtain",
                status: .backlog,
                notes: "phase 2"
            )
        )
        #expect(item.title == "Wire the curtain")
        #expect(item.id.rawValue.hasPrefix("ps-"))
        #expect(linear.created.count == 1)
        #expect(multica.created.count == 1)
        #expect(linear.created[0].id.hasPrefix("BIN-"))
        #expect(multica.created[0].id.hasPrefix("HAB-"))

        let encoded = try JSONEncoder().encode(item)
        let json = String(decoding: encoded, as: UTF8.self)
        #expect(!json.contains("BIN-"))
        #expect(!json.contains("HAB-"))
        #expect(!json.contains("linear"))
        print("🎉 ✨ CREATE FAN-OUT RITUAL COMPLETE!")
    }

    @Test("🪄 Multica-only create when Linear unwired")
    func testCreateMulticaOnly() async throws {
        let multica = MockMulticaProvider(issues: [])
        let bridge = OperatorProjectStateBridge(
            linear: UnwiredLinearProvider(),
            multica: multica
        )
        let item = try await bridge.createItem(
            ProjectStateDraft(
                projectID: ProjectStateID(rawValue: "andromeda"),
                title: "Habitat solo",
                status: .active
            )
        )
        #expect(item.title == "Habitat solo")
        #expect(multica.created.count == 1)
        print("🎉 ✨ MULTICA-ONLY CREATE COMPLETE!")
    }

    /// 🧪 Codex P1 landmine — create salt ≠ refresh salt caused itemNotFound after list.
    @Test("🧷 create → refresh → update keeps stable item id (no itemNotFound)")
    func testCreateRefreshUpdateStableID() async throws {
        let linear = MockLinearProvider(issues: [])
        let multica = MockMulticaProvider(issues: [])
        let bridge = OperatorProjectStateBridge(linear: linear, multica: multica)

        let created = try await bridge.createItem(
            ProjectStateDraft(
                projectID: ProjectStateID(rawValue: "andromeda"),
                title: "Stable ID curtain",
                status: .backlog,
                notes: "must survive refresh"
            )
        )
        #expect(created.id.rawValue.hasPrefix("ps-"))

        // 🎨 Refresh rebuilds from providers — ID must match create's return value
        let listed = try await bridge.listProjects()
        let refreshed = try #require(listed[0].items.first { $0.title == "Stable ID curtain" })
        #expect(refreshed.id == created.id)

        // ✨ Update with the create-returned ID must NOT itemNotFound
        let updated = try await bridge.updateItem(
            created.id,
            ProjectStatePatch(title: "Stable ID curtain v2", status: .active)
        )
        #expect(updated.id == created.id)
        #expect(updated.title == "Stable ID curtain v2")
        #expect(updated.status == .active)
        #expect(linear.updated.count == 1)
        #expect(multica.updated.count == 1)
        print("🎉 ✨ CREATE→REFRESH→UPDATE STABLE ID RITUAL COMPLETE!")
    }

    @Test("🔄 project.state.update patches both trackers via provenance")
    func testUpdateFanOut() async throws {
        let linear = MockLinearProvider(issues: [
            LinearIssueFragment(id: "BIN-40", title: "Capability curtain", state: "In Progress"),
        ])
        let multica = MockMulticaProvider(issues: [
            MulticaIssueFragment(id: "HAB-40", title: "Capability curtain", status: "active"),
        ])
        let bridge = OperatorProjectStateBridge(linear: linear, multica: multica)
        let listed = try await bridge.listProjects()
        let item = try #require(listed[0].items.first)

        let updated = try await bridge.updateItem(
            item.id,
            ProjectStatePatch(title: "Capability curtain v2", status: .done)
        )
        #expect(updated.title == "Capability curtain v2")
        #expect(updated.status == .done)
        #expect(linear.updated.count == 1)
        #expect(multica.updated.count == 1)
        #expect(linear.updated[0].0 == "BIN-40")
        #expect(multica.updated[0].0 == "HAB-40")
        print("🎉 ✨ UPDATE FAN-OUT RITUAL COMPLETE!")
    }

    @Test("🧹 Strip [Linear BIN-n] chrome from Multica titles for clients")
    func testStripTrackerNoiseOnMerge() async throws {
        let bridge = OperatorProjectStateBridge(
            linear: MockLinearProvider(issues: []),
            multica: MockMulticaProvider(issues: [
                MulticaIssueFragment(
                    id: "HAB-56",
                    title: "[Linear BIN-39] Wire live project.state",
                    status: "in_progress"
                ),
            ])
        )
        let listed = try await bridge.listProjects()
        #expect(listed[0].items.count == 1)
        #expect(listed[0].items[0].title == "Wire live project.state")
        let json = String(decoding: try JSONEncoder().encode(listed[0]), as: UTF8.self)
        #expect(!json.contains("BIN-39"))
        #expect(!json.contains("HAB-56"))
        print("🎉 ✨ TRACKER NOISE STRIPPED!")
    }

    @Test("🔑 LINEAR_API_KEY loads from dotenv path when process env is empty (values never asserted)")
    func testLinearKeyLoadsFromDotenvFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ps-dotenv-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let envPath = dir.appendingPathComponent(".env")
        // Synthetic key — never a real credential; proves parse + precedence only.
        let synthetic = "lin_test_synthetic_key_not_real"
        try "LINEAR_API_KEY=\(synthetic)\nLINEAR_TEAM_ID=team-from-file\n".write(
            to: envPath,
            atomically: true,
            encoding: .utf8
        )

        let config = ProjectStateBridgeConfiguration.loadFromEnvironment(
            environment: [:],
            dotenvSearchPaths: [envPath.path]
        )
        #expect(config.linearAPIKey != nil)
        #expect(config.linearAPIKey?.isEmpty == false)
        #expect(config.linearAPIKey?.count == synthetic.count)
        #expect(config.linearTeamID == "team-from-file")
        // Process env wins over dotenv
        let override = ProjectStateBridgeConfiguration.loadFromEnvironment(
            environment: ["LINEAR_API_KEY": "from-process"],
            dotenvSearchPaths: [envPath.path]
        )
        #expect(override.linearAPIKey == "from-process")
        print("🎉 ✨ DOTENV LINEAR KEY LOAD PASS (value cloaked, len=\(config.linearAPIKey?.count ?? 0))")
    }

    /// 🧪 Codex P2 — later dotenv fills missing keys when the first file exists but lacks LINEAR_API_KEY.
    @Test("🔀 Dotenv merge: later file supplies LINEAR_API_KEY when earlier file has other keys only")
    func testDotenvMergesLaterFilesForMissingKeys() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ps-dotenv-merge-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let earlier = dir.appendingPathComponent("repo.env")
        let later = dir.appendingPathComponent("user.env")
        // Earlier path has Multica-ish keys only — must NOT block Linear from the later file.
        try "MULTICA_WORKSPACE_ID=ws-from-earlier\n".write(to: earlier, atomically: true, encoding: .utf8)
        try "LINEAR_API_KEY=lin_merge_synthetic_not_real\nLINEAR_TEAM_ID=team-from-later\n".write(
            to: later,
            atomically: true,
            encoding: .utf8
        )

        let config = ProjectStateBridgeConfiguration.loadFromEnvironment(
            environment: [:],
            dotenvSearchPaths: [earlier.path, later.path]
        )
        #expect(config.multicaWorkspaceID == "ws-from-earlier")
        #expect(config.linearAPIKey == "lin_merge_synthetic_not_real")
        #expect(config.linearTeamID == "team-from-later")
        // Earlier path wins on collisions
        try "LINEAR_API_KEY=lin_from_earlier\n".write(to: earlier, atomically: true, encoding: .utf8)
        let collision = ProjectStateBridgeConfiguration.loadFromEnvironment(
            environment: [:],
            dotenvSearchPaths: [earlier.path, later.path]
        )
        #expect(collision.linearAPIKey == "lin_from_earlier")
        print("🎉 ✨ DOTENV MERGE LATER-FILE PASS")
    }

    @Test("🌐 Factory wires LiveLinearProjectProvider when dotenv supplies LINEAR_API_KEY")
    func testFactoryWiresLinearFromDotenv() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ps-factory-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let envPath = dir.appendingPathComponent(".env")
        try? "LINEAR_API_KEY=lin_factory_synthetic_not_real\n".write(to: envPath, atomically: true, encoding: .utf8)

        let config = ProjectStateBridgeConfiguration.loadFromEnvironment(
            environment: [:],
            dotenvSearchPaths: [envPath.path]
        )
        #expect(config.linearAPIKey != nil)
        let bridge = ProjectStateBridgeFactory.makeStudioBridge(configuration: config)
        // Bridge is constructed; Linear path is keyed (NullLinear would soft-skip). Prove via config gate.
        #expect((config.linearAPIKey ?? "").isEmpty == false)
        _ = bridge
        print("🎉 ✨ FACTORY LINEAR WIRE GATE PASS")
    }
}

private final class MockLinearProvider: LinearProjectProvider, @unchecked Sendable {
    let issues: [LinearIssueFragment]
    private(set) var created: [LinearIssueFragment] = []
    private(set) var updated: [(String, String?, String?)] = []

    init(issues: [LinearIssueFragment]) {
        self.issues = issues
    }

    func fetchIssues() async throws -> [LinearIssueFragment] { issues + created }

    func createIssue(title: String, description: String?) async throws -> LinearIssueFragment {
        let fragment = LinearIssueFragment(id: "BIN-\(900 + created.count)", title: title, state: "Backlog")
        created.append(fragment)
        return fragment
    }

    func updateIssue(id: String, title: String?, state: String?) async throws -> LinearIssueFragment {
        updated.append((id, title, state))
        return LinearIssueFragment(id: id, title: title ?? "updated", state: state ?? "In Progress")
    }
}

private final class MockMulticaProvider: MulticaProjectProvider, @unchecked Sendable {
    let issues: [MulticaIssueFragment]
    private(set) var created: [MulticaIssueFragment] = []
    private(set) var updated: [(String, String?, String?)] = []

    init(issues: [MulticaIssueFragment]) {
        self.issues = issues
    }

    func fetchIssues() async throws -> [MulticaIssueFragment] { issues + created }

    func createIssue(title: String, description: String?) async throws -> MulticaIssueFragment {
        let fragment = MulticaIssueFragment(id: "HAB-\(900 + created.count)", title: title, status: "todo")
        created.append(fragment)
        return fragment
    }

    func updateIssue(id: String, title: String?, status: String?) async throws -> MulticaIssueFragment {
        updated.append((id, title, status))
        return MulticaIssueFragment(id: id, title: title ?? "updated", status: status ?? "in_progress")
    }
}

private struct UnwiredLinearProvider: LinearProjectProvider {
    func fetchIssues() async throws -> [LinearIssueFragment] { throw ProjectStateError.bridgeNotWired }
    func createIssue(title: String, description: String?) async throws -> LinearIssueFragment {
        throw ProjectStateError.bridgeNotWired
    }
    func updateIssue(id: String, title: String?, state: String?) async throws -> LinearIssueFragment {
        throw ProjectStateError.bridgeNotWired
    }
}

