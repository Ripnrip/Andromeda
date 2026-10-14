/**
 * SkillRegistry — observe-first inventory for ritual skills (HAB-598).
 *
 * Mirrors MCPServerRegistry's observe-only contract: list / scan, never invoke
 * or mutate skill contents. Knowledge-sync consolidation starts as a visible
 * capability row; fan-out destinations stay behind the curtain / multibrain.
 *
 * Review 5513453513:
 * - P1-1: disk scans surface a typed `SkillScanStatus` — failures are never
 *   collapsed into `presentOnDisk == false` / `missingCount` ambiguity.
 * - P1-2: the registry is an actor — no `@unchecked Sendable` mutable-state
 *   escape hatch; all stored dependencies are immutable and `Sendable`.
 */

import Foundation

// MARK: - Typed scan outcome (P1-1)

/// Typed failure codes for a skills-root scan.
public enum SkillScanFailureCode: String, Sendable, Codable, Equatable {
    /// The configured skills root does not exist on this volume.
    case rootMissing
    /// The root exists but its contents could not be listed (permissions / IO).
    case rootUnreadable
}

/// Typed scan outcome — `ok` or a coded failure with human-readable detail.
public enum SkillScanStatus: Sendable, Equatable {
    case ok
    case failed(code: SkillScanFailureCode, detail: String)

    public var isOK: Bool {
        if case .ok = self { return true }
        return false
    }
}

/// Probe result for a skills root: typed status plus discovered paths.
/// A failed discovery always carries an empty path map and a non-`.ok` status —
/// callers must read `status`, never infer health from the path map alone.
public struct SkillPathDiscovery: Sendable, Equatable {
    public let status: SkillScanStatus
    public let paths: [String: String]

    public static func succeeded(_ paths: [String: String]) -> SkillPathDiscovery {
        SkillPathDiscovery(status: .ok, paths: paths)
    }

    public static func failed(code: SkillScanFailureCode, detail: String) -> SkillPathDiscovery {
        SkillPathDiscovery(status: .failed(code: code, detail: detail), paths: [:])
    }
}

// MARK: - Enumeration

/// Injectable skill-path probe — production walks `~/.claude/skills`; tests fixture.
public protocol SkillPathEnumerating: Sendable {
    /// Typed probe of the skills root (P1-1 — errors surface, never swallowed).
    func discoverSkills() -> SkillPathDiscovery
}

/// Hermetic empty enumerator (successful scan of an empty root).
public struct NullSkillPathEnumerator: SkillPathEnumerating {
    public init() {}
    public func discoverSkills() -> SkillPathDiscovery { .succeeded([:]) }
}

/// Fixture enumerator for Swift Testing.
public struct MockSkillPathEnumerator: SkillPathEnumerating {
    private let discovery: SkillPathDiscovery

    public init(discovery: SkillPathDiscovery) {
        self.discovery = discovery
    }

    public init(paths: [String: String] = [:]) {
        self.discovery = .succeeded(paths)
    }

    public init(failed code: SkillScanFailureCode, detail: String) {
        self.discovery = .failed(code: code, detail: detail)
    }

    public func discoverSkills() -> SkillPathDiscovery { discovery }
}

/// Walks Claude skills home (observe only) with typed failure surfacing (P1-1).
public struct ClaudeSkillsPathEnumerator: SkillPathEnumerating {
    public let skillsRoot: URL

    public init(
        skillsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/skills", isDirectory: true)
    ) {
        self.skillsRoot = skillsRoot
    }

    public func discoverSkills() -> SkillPathDiscovery {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: skillsRoot.path, isDirectory: &isDir), isDir.boolValue else {
            return .failed(code: .rootMissing, detail: "no skills directory at \(skillsRoot.path)")
        }
        do {
            let kids = try fm.contentsOfDirectory(
                at: skillsRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            var out: [String: String] = [:]
            for url in kids {
                var dirFlag: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &dirFlag), dirFlag.boolValue else { continue }
                out[url.lastPathComponent.lowercased()] = url.path
            }
            return .succeeded(out)
        } catch {
            return .failed(code: .rootUnreadable, detail: error.localizedDescription)
        }
    }
}

// MARK: - Scan result

/// Crystallized output of `skill.list` / scan. `status` distinguishes a
/// successful empty scan from a failed one (P1-1): on failure the catalog rows
/// are still emitted (visible as absent) but `missingCount` is not evidence —
/// read `status`.
public struct SkillRegistryScanResult: Sendable, Equatable {
    public let status: SkillScanStatus
    public let entities: [SkillEntity]
    public let presentCount: Int
    public let missingCount: Int
    public let scannedAt: Date

    public init(entities: [SkillEntity], status: SkillScanStatus = .ok, scannedAt: Date = Date()) {
        self.entities = entities
        self.status = status
        self.presentCount = entities.filter(\.presentOnDisk).count
        self.missingCount = entities.filter { !$0.presentOnDisk }.count
        self.scannedAt = scannedAt
    }
}

// MARK: - Registry (P1-2: actor, not @unchecked Sendable)

/// Observe-only skill roster. Seeds the four ritual kinds; marks disk presence.
/// Actor-isolated (P1-2): all stored dependencies are `let` and `Sendable`,
/// so isolation is compiler-verified rather than `@unchecked`.
public actor SkillRegistry {
    private let enumerator: any SkillPathEnumerating
    private let source: SkillSource
    private let clock: @Sendable () -> Date

    public init(
        enumerator: any SkillPathEnumerating = NullSkillPathEnumerator(),
        source: SkillSource = .claude,
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        self.enumerator = enumerator
        self.source = source
        self.clock = clock
    }

    /// Capability IDs clients may list (curtain-stable).
    public nonisolated static var catalogCapabilityIDs: [String] {
        SkillKind.allCases.map(\.capabilityID)
    }

    /// Scan ritual skills against discovered paths.
    public func scan() -> SkillRegistryScanResult {
        let now = clock()
        let discovery = enumerator.discoverSkills()
        let entities: [SkillEntity] = SkillKind.allCases.map { kind in
            let path = discovery.paths[kind.rawValue]
            return SkillEntity(
                id: kind.capabilityID,
                kind: kind,
                path: path,
                source: source,
                presentOnDisk: path != nil,
                scannedAt: now
            )
        }
        return SkillRegistryScanResult(entities: entities, status: discovery.status, scannedAt: now)
    }

    /// List capability ids (always the full catalog — missing ones stay visible as absent).
    public func listCapabilityIDs() -> [String] {
        scan().entities.map(\.capabilityID)
    }
}
