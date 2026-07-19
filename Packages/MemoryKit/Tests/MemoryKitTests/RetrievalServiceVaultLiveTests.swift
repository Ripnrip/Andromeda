/**
 * 🎭 RetrievalServiceVaultLiveTests - The Live Vault Recall Proof
 *
 * "No mocks, no fog machines — we send the real ripgrep into the real
 *  SecondBrain vault and prove that a needle the hot store never learned
 *  still surfaces from the shelves. This is the anti-stale-binary sentinel."
 *
 * - The Enchanted Recall Observatory of Anima
 *
 * Regression guard for the STALE-BINARY bug: an old hot-store-only build
 * returned "No memories matched cloak" even though the vault holds it.
 * The current source runs a real rg vault fallback — this test proves it end
 * to end against the on-disk store + real LocalProcessRunner + live vault.
 *
 * Hermetic by design: skips (does not fail) when the vault dir or rg binary
 * are absent, so CI without the SecondBrain checkout degrades gracefully.
 */

import Testing
@testable import MemoryKit
import Foundation

@Suite("🌐 Live Vault Recall (real rg, real vault)")
struct RetrievalServiceVaultLiveTests {

    private static let vaultURL = URL(
        fileURLWithPath: ("~/Developer/SecondBrain" as NSString).expandingTildeInPath,
        isDirectory: true
    )
    private static let ripgrep = "/opt/homebrew/bin/rg"

    /// True only when both the live vault dir and the rg binary are present.
    private static func liveEnvironmentAvailable() -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let vaultOK = fm.fileExists(atPath: vaultURL.path, isDirectory: &isDir) && isDir.boolValue
        let rgOK = fm.isExecutableFile(atPath: ripgrep)
        return vaultOK && rgOK
    }

    @Test("🔎 'cloak' recall surfaces live vault hits when the hot store never learned it")
    func testCloakRecallSurfacesVaultHits() async throws {
        guard Self.liveEnvironmentAvailable() else {
            print("🌙 Skipping live vault recall — vault (\(Self.vaultURL.path)) or rg (\(Self.ripgrep)) absent.")
            return
        }

        // Fresh on-disk hot store in a temp dir — hermetic, and deliberately empty so the
        // ONLY way "cloak" can surface is the real vault ripgrep fallback (reproduces the
        // stale hot-store-only failure mode, then proves the live vault path recovers it).
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("anima-cloak-live-\(UUID().uuidString).store")
        let container = try SwiftDataContainer.createOnDisk(at: storeURL)
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(
                    at: storeURL.deletingLastPathComponent()
                        .appendingPathComponent(storeURL.lastPathComponent + suffix)
                )
            }
        }

        let retrieval = RetrievalService(
            container: container,
            vaultURL: Self.vaultURL,
            processRunner: LocalProcessRunner(),
            ripgrepExecutable: Self.ripgrep
        )

        let result = try await retrieval.recallMemory(
            RecallQuery(text: "cloak", limit: 12, includeVaultFallback: true)
        )

        let vaultHits = result.hits.filter { $0.source == .vault }
        print("✅ 'cloak' recall — total hits=\(result.hits.count), vaultHitCount=\(result.vaultHitCount), hotHitCount=\(result.hotHitCount), degraded=\(result.vaultDegraded)")
        for hit in vaultHits.prefix(3) {
            let snippet = hit.narrative.prefix(120)
            print("   📜 [\(hit.source.rawValue)] \(hit.path ?? "?"): \(snippet)")
        }

        #expect(result.vaultDegraded == false)
        #expect(result.vaultHitCount > 0)
        #expect(!vaultHits.isEmpty)
        #expect(vaultHits.allSatisfy { $0.narrative.lowercased().contains("cloak") })
    }
}
