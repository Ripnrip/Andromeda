/**
 * 🎭 The CaptureService - The Hot-Path Memory Quill
 *
 * "Ink meets parchment in a single breath: hash the tale, seal the block,
 * return the id before the cold world even stirs. No vault walks, no vector
 * pilgrimages — only the local ledger's ACID curtain call."
 *
 * - The Theatrical Capture Virtuoso of Anima
 */

import Foundation
import CryptoKit

/// 🆔 MemoryID — the UUID handed back the instant a capture lands in the hot store.
public typealias MemoryID = UUID

/// 🌩️ Errors from the transactional store_memory rite.
public enum CaptureServiceError: Error, LocalizedError, Sendable {
    case emptyNarrative
    case storage(AnimaStorageError)

    public var errorDescription: String? {
        switch self {
        case .emptyNarrative:
            return "🌩️ Cannot capture an empty narrative — the quill refuses blank parchment."
        case .storage(let underlying):
            return underlying.errorDescription
        }
    }
}

/// 🌟 CaptureService — transactional `store_memory` for Anima's hot path.
///
/// Flow: content_hash(narrative) → SwiftDataContainer.insert → optional AnimaLedger seal → MemoryID.
/// Explicitly does **not** touch Obsidian, Qdrant, LadybugDB, or CloudKit.
@available(macOS 14.0, iOS 17.0, *)
public actor CaptureService {
    /// 💎 The hot SwiftData vault (actor-isolated ACID journal).
    private let container: SwiftDataContainer

    /// 🛡️ Optional Merkle/Anima seal ledger. When nil, inserts still succeed without sealing.
    private var ledger: AnimaLedger?

    /// 👑 Latest seal after the most recent successful capture (nil if no ledger or never sealed).
    public private(set) var latestSeal: String?

    /// 🔮 Conjure a capture service bound to a vault, optionally with an integrity ledger.
    /// - Parameters:
    ///   - container: Actor-isolated SwiftData hot store.
    ///   - ledger: When provided, each successful insert appends a sealed AnimaBlock.
    public init(container: SwiftDataContainer, ledger: AnimaLedger? = AnimaLedger()) {
        self.container = container
        self.ledger = ledger
        self.latestSeal = ledger?.latestSeal
    }

    /// 🧮 Compute the deterministic content_hash for a narrative body.
    /// Format: `sha256:<hex>` — the join key across hot store, vault, and indexes.
    public nonisolated static func contentHash(for narrative: String) -> String {
        let digest = SHA256.hash(data: Data(narrative.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex)"
    }

    /// 📥 store_memory — hash → insert → seal (if ledger available) → return MemoryID immediately.
    ///
    /// Hot-path boundary: this method only talks to `SwiftDataContainer` and optional `AnimaLedger`.
    /// It never invokes Obsidian writers, QdrantIndexer, LadybugIndexer, or CloudKitSyncEngine.
    ///
    /// - Parameters:
    ///   - narrative: The episodic text to capture (must be non-empty).
    ///   - project: Project / workspace label.
    ///   - agent: Capturing agent identity.
    ///   - provenance: Source metadata string.
    ///   - visibility: Override; defaults to `private`.
    ///   - tags: Optional classification tags.
    ///   - id: Optional client-supplied MemoryID (defaults to a fresh UUID).
    /// - Returns: The MemoryID of the persisted episodic record.
    @discardableResult
    public func storeMemory(
        narrative: String,
        project: String,
        agent: String,
        provenance: String,
        visibility: String = VisibilityClass.private.rawValue,
        tags: [String] = [],
        id: UUID = UUID()
    ) async throws -> MemoryID {
        let trimmedNarrative = narrative.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNarrative.isEmpty else {
            throw CaptureServiceError.emptyNarrative
        }

        // 🎨 Resolve visibility: honor override when it is a known class; else cloak as private.
        let resolvedVisibility = VisibilityClass(rawValue: visibility)?.rawValue
            ?? VisibilityClass.private.rawValue

        // ✨ Hash the tale before the curtain rises
        let contentHash = Self.contentHash(for: trimmedNarrative)
        print("🌐 ✨ STORE_MEMORY AWAKENS! hash=\(contentHash) visibility=\(resolvedVisibility)")

        let snapshot = AnimaEpisodicRecordSnapshot(
            id: id,
            contentHash: contentHash,
            createdAt: Date(),
            project: project,
            agent: agent,
            narrative: trimmedNarrative,
            visibility: resolvedVisibility,
            provenance: provenance,
            tags: tags,
            materializedPath: nil
        )

        // 💎 ACID insert into the hot vault — uniqueness enforced on content_hash
        do {
            try await container.insert(snapshot, checkUniqueHash: true)
        } catch let storageError as AnimaStorageError {
            throw CaptureServiceError.storage(storageError)
        } catch {
            throw CaptureServiceError.storage(.saveFailed(error.localizedDescription))
        }

        // 🛡️ Seal the block when a ledger is available; otherwise skip without blocking return
        if var activeLedger = ledger {
            let block = activeLedger.append(contentHash: contentHash, id: id)
            ledger = activeLedger
            latestSeal = block.seal
            print("🛡️ ✨ MEMORY SEALED! seal=\(block.seal.prefix(16))…")
        } else {
            latestSeal = nil
            print("🌙 ⚠️ Gentle reminder: no AnimaLedger — capture persisted without seal.")
        }

        print("🎉 ✨ STORE_MEMORY MASTERPIECE COMPLETE! id=\(id)")
        return id
    }

    /// 🔍 Peek at the current AnimaLedger (copy), if one was configured.
    public func currentLedger() -> AnimaLedger? {
        ledger
    }

    /// 🛡️ Verify the seal chain when a ledger is present.
    public func verifySealChain() -> Result<Void, AnimaSeal.ValidationError>? {
        ledger?.verify()
    }
}
