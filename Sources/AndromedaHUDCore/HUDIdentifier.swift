import CryptoKit
import Foundation
import MemoryKit
import SwiftUI

/**
 * 🎭 The HUDIdentifier - The Stage-Door Ledger
 *
 * "Every pane and control wears its name at the door,
 * so the App Control ushers never guess where to go."
 *
 * - The Spellbinding Museum Director of Glass
 */

/// The `hud.<pane>.<control>` accessibility-identifier catalogue (HAB-838).
///
/// Static surfaces use named constants. Data-backed rows use typed factories
/// whose suffix is a stable SHA-256 digest; raw queries, memory narratives,
/// project titles, and tracker identifiers never enter the AX identifier.
public struct HUDIdentifier: Hashable, Sendable {
    public let rawValue: String

    private init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The pill's root container (`.contain` — level-1 keeps children visible).
    public static let root = Self(rawValue: "hud.root")
    /// The command TextField.
    public static let searchField = Self(rawValue: "hud.search.field")
    /// The fleet-pulse status dot.
    public static let fleetPulse = Self(rawValue: "hud.fleetPulse")
    /// The transient activation-feedback line.
    public static let feedback = Self(rawValue: "hud.feedback")
    /// The frosted results panel (`.contain` at level-1).
    public static let resultsContainer = Self(rawValue: "hud.results.container")
    /// The recent-queries pane.
    public static let resultsRecent = Self(rawValue: "hud.results.recent")
    /// Namespace for an opaque recent-query row identifier.
    public static let resultsRecentItem = Self(rawValue: "hud.results.recent.item")
    /// The shared empty / error / loading / success row.
    public static let resultsStatus = Self(rawValue: "hud.results.status")
    /// Namespace for an opaque recalled-memory row identifier.
    public static let resultsHit = Self(rawValue: "hud.results.hit")
    /// The project.state pane.
    public static let resultsProjects = Self(rawValue: "hud.results.projects")
    /// Namespace for an opaque project.state item identifier.
    public static let resultsProjectsItem = Self(rawValue: "hud.results.projects.item")

    /// Static catalogue entries. Dynamic row identifiers are recognized by
    /// their namespace plus a fixed-width lower-case hexadecimal digest.
    public static let allCases: [Self] = [
        .root,
        .searchField,
        .fleetPulse,
        .feedback,
        .resultsContainer,
        .resultsRecent,
        .resultsRecentItem,
        .resultsStatus,
        .resultsHit,
        .resultsProjects,
        .resultsProjectsItem,
    ]

    /// Stable identity for a recent row without exposing the query.
    public static func recentQuery(_ query: String) -> Self {
        opaque(namespace: resultsRecentItem, components: [query])
    }

    /// Stable identity for a memory row, keyed only by `MemoryHit.ID`.
    ///
    /// Bounded stability: hot-store hits carry their durable `memoryID` /
    /// `contentHash`, but `RetrievalService.parseRipgrepJSONLines` mints a
    /// fresh `MemoryHit.id` per vault recall, so a vault row's identifier
    /// changes when the query is re-run. Keying on `MemoryHit.ID` (not on the
    /// narrative) keeps the row identity stable across re-render and reorder;
    /// making it stable across *recalls* is a MemoryKit change, out of this
    /// slice's scope.
    public static func memoryHit(_ id: MemoryHit.ID) -> Self {
        opaque(namespace: resultsHit, components: [id.uuidString.lowercased()])
    }

    /// Stable identity for a project result without exposing tracker IDs or
    /// titles. Item IDs are scoped within a project, so both typed IDs are
    /// hashed behind the namespace.
    public static func projectItem(
        projectID: ProjectState.ID,
        itemID: ProjectStateItem.ID
    ) -> Self {
        opaque(namespace: resultsProjectsItem, components: [projectID.rawValue, itemID.rawValue])
    }

    /// True only for a static catalogue spelling or a well-shaped opaque row
    /// identifier produced by one of the typed factories.
    public static func recognizes(_ rawValue: String) -> Bool {
        allCases.contains { $0.rawValue == rawValue }
            || [resultsRecentItem, resultsHit, resultsProjectsItem].contains { namespace in
                let prefix = namespace.rawValue + "."
                guard rawValue.hasPrefix(prefix) else { return false }
                let digest = rawValue.dropFirst(prefix.count)
                return digest.count == digestLength
                    && digest.allSatisfy { $0.isHexDigit && !$0.isUppercase }
            }
    }

    private static let digestLength = 24

    private static func opaque(namespace: Self, components: [String]) -> Self {
        var bytes = Data()
        for component in components {
            let componentBytes = Data(component.utf8)
            var length = UInt64(componentBytes.count).bigEndian
            withUnsafeBytes(of: &length) { bytes.append(contentsOf: $0) }
            bytes.append(componentBytes)
        }
        let digest = SHA256.hash(data: bytes)
            .prefix(digestLength / 2)
            .map { String(format: "%02x", $0) }
            .joined()
        return Self(rawValue: namespace.rawValue + "." + digest)
    }
}

public extension View {
    /// 🌟 Stamps a catalogue spelling onto glass - the only sanctioned way to
    /// attach a `hud.*` identifier, so raw strings can never creep back in.
    func hudIdentifier(_ id: HUDIdentifier) -> some View {
        accessibilityIdentifier(id.rawValue)
    }
}
