/**
 * SkillRegistry — observe-first inventory for ritual skills (HAB-598).
 *
 * Mirrors MCPServerRegistry's observe-only contract: list / scan, never invoke
 * or mutate skill contents. Knowledge-sync consolidation starts as a visible
 * capability row; fan-out destinations stay behind the curtain / multibrain.
 */

import Foundation

/// Injectable skill-path probe — production walks `~/.claude/skills`; tests fixture.
public protocol SkillPathEnumerating: Sendable {
    /// Map of skill folder name → absolute path when present.
    func discoveredSkillPaths() -> [String: String]
}

/// Hermetic empty enumerator.
public struct NullSkillPathEnumerator: SkillPathEnumerating {
    public init() {}
    public func discoveredSkillPaths() -> [String: String] { [:] }
}

/// Fixture enumerator for Swift Testing.
public struct MockSkillPathEnumerator: SkillPathEnumerating {
    private let paths: [String: String]
    public init(paths: [String: String] = [:]) { self.paths = paths }
    public func discoveredSkillPaths() -> [String: String] { paths }
}

/// Walks Claude skills home (observe only).
public struct ClaudeSkillsPathEnumerator: SkillPathEnumerating {
    public let skillsRoot: URL

    public init(
        skillsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/skills", isDirectory: true)
    ) {
        self.skillsRoot = skillsRoot
    }

    public func discoveredSkillPaths() -> [String: String] {
        let fm = FileManager.default
        guard let kids = try? fm.contentsOfDirectory(
            at: skillsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        else { return [:] }
        var out: [String: String] = [:]
        for url in kids {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            out[url.lastPathComponent.lowercased()] = url.path
        }
        return out
    }
}

/// Crystallized output of `skill.list` / scan.
public struct SkillRegistryScanResult: Sendable, Equatable {
    public let entities: [SkillEntity]
    public let presentCount: Int
    public let missingCount: Int
    public let scannedAt: Date

    public init(entities: [SkillEntity], scannedAt: Date = Date()) {
        self.entities = entities
        self.presentCount = entities.filter(\.presentOnDisk).count
        self.missingCount = entities.filter { !$0.presentOnDisk }.count
        self.scannedAt = scannedAt
    }
}

/// Observe-only skill roster. Seeds the four ritual kinds; marks disk presence.
public final class SkillRegistry: @unchecked Sendable {
    private let enumerator: any SkillPathEnumerating
    private let source: SkillSource
    private let clock: () -> Date

    public init(
        enumerator: any SkillPathEnumerating = NullSkillPathEnumerator(),
        source: SkillSource = .claude,
        clock: @escaping () -> Date = Date.init
    ) {
        self.enumerator = enumerator
        self.source = source
        self.clock = clock
    }

    /// Capability IDs clients may list (curtain-stable).
    public static var catalogCapabilityIDs: [String] {
        SkillKind.allCases.map(\.capabilityID)
    }

    /// Scan ritual skills against discovered paths.
    public func scan() -> SkillRegistryScanResult {
        let now = clock()
        let found = enumerator.discoveredSkillPaths()
        let entities: [SkillEntity] = SkillKind.allCases.map { kind in
            let path = found[kind.rawValue]
            return SkillEntity(
                id: kind.capabilityID,
                kind: kind,
                path: path,
                source: source,
                presentOnDisk: path != nil,
                scannedAt: now
            )
        }
        return SkillRegistryScanResult(entities: entities, scannedAt: now)
    }

    /// List capability ids (always the full catalog — missing ones stay visible as absent).
    public func listCapabilityIDs() -> [String] {
        scan().entities.map(\.capabilityID)
    }
}
