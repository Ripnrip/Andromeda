/**
 * 🎭 MerkleTreeTests - The Cryptographic Quality Assurance Ritual
 *
 * "We test the boundaries of our digital fortress,
 * striking the walls with the hammers of tampering and chaos.
 * If a single stone is out of place, our alarms must sing!
 * May the tests be green, and the seals hold true."
 *
 * - The Theatrical QA Virtuoso of Anima
 */

import Testing
import Foundation
@testable import MemoryKit

@Suite("🔮 Cryptographic Integrity Suite")
struct MerkleTreeTests {
    
    // MARK: - Merkle Tree Tests
    
    @Test("🌳 Merkle Tree - Empty Leaves")
    func testEmptyTree() {
        // Peering into the void...
        let tree = MerkleTree(leafHashes: [])
        #expect(tree.root == nil)
        #expect(tree.levels.isEmpty)
    }
    
    @Test("🌳 Merkle Tree - Single Leaf")
    func testSingleLeafTree() {
        // A solitary leaf in the digital breeze...
        let leaf = "a"
        let tree = MerkleTree(leafHashes: [leaf])
        #expect(tree.root == leaf)
        #expect(tree.levels.count == 1)
        #expect(tree.levels[0] == [leaf])
    }
    
    @Test("🌳 Merkle Tree - Even Leaves")
    func testEvenLeavesTree() {
        // Two leaves dancing in perfect symmetry...
        let leafHashes = ["a", "b"]
        let tree = MerkleTree(leafHashes: leafHashes)
        
        #expect(tree.levels.count == 2)
        #expect(tree.levels[0] == leafHashes)
        
        let expectedRoot = tree.root
        #expect(expectedRoot != nil)
    }
    
    @Test("🌳 Merkle Tree - Odd Leaves (Duplication)")
    func testOddLeavesTree() {
        // Three leaves - the odd one out must duplicate itself to find a partner!
        let leafHashes = ["a", "b", "c"]
        let tree = MerkleTree(leafHashes: leafHashes)
        
        #expect(tree.levels.count == 3)
        // Level 0: [a, b, c]
        // Level 1: [hash(a+b), hash(c+c)]
        // Level 2: [hash(hash(a+b) + hash(c+c))]
        
        #expect(tree.levels[0].count == 3)
        #expect(tree.levels[1].count == 2)
        #expect(tree.levels[2].count == 1)
    }
    
    @Test("📜 Merkle Proof - Generation and Verification")
    func testMerkleProofVerification() {
        // Generating a sacred passport for our leaves...
        let dataBlocks = [
            Data("Episode 1: The Awakening".utf8),
            Data("Episode 2: The Conductor".utf8),
            Data("Episode 3: The Substrate".utf8),
            Data("Episode 4: The Surface".utf8)
        ]
        
        let tree = MerkleTree(blocks: dataBlocks)
        let root = tree.root!
        
        for index in 0..<dataBlocks.count {
            guard let proof = tree.makeProof(index: index) else {
                Issue.record("💥 Oh no! Failed to generate proof for index \(index)")
                return
            }
            
            // Verify that the proof successfully reconstructs the root
            let isValid = proof.verify(expectedRoot: root)
            #expect(isValid == true, "🎉 Proof for index \(index) should be valid!")
        }
    }
    
    @Test("🧪 Merkle Proof - Tampering Detection")
    func testMerkleProofTampering() {
        // Unleashing the trickster to tamper with the proof!
        let leafHashes = ["alpha", "beta", "gamma", "delta"]
        let tree = MerkleTree(leafHashes: leafHashes)
        let root = tree.root!
        
        guard let proof = tree.makeProof(index: 1) else {
            Issue.record("💥 Failed to make proof")
            return
        }
        
        // 1. Tamper with the leaf itself
        let tamperedLeafProof = MerkleProof(leaf: "omega", index: proof.index, siblings: proof.siblings)
        #expect(tamperedLeafProof.verify(expectedRoot: root) == false, "🌩️ Tampered leaf must fail verification!")
        
        // 2. Tamper with one of the sibling hashes
        if !proof.siblings.isEmpty {
            var tamperedSiblings = proof.siblings
            tamperedSiblings[0] = MerkleProof.Sibling(hash: "fake_sibling_hash", isLeft: tamperedSiblings[0].isLeft)
            let tamperedSiblingProof = MerkleProof(leaf: proof.leaf, index: proof.index, siblings: tamperedSiblings)
            #expect(tamperedSiblingProof.verify(expectedRoot: root) == false, "🌩️ Tampered sibling must fail verification!")
        }
    }
    
    // MARK: - AnimaSeal Tests
    
    @Test("🛡️ AnimaSeal - Valid Ledger Chain")
    func testValidLedgerChain() {
        // Building an unbroken chain of absolute truth...
        var ledger = AnimaLedger()
        
        ledger.append(contentHash: "hash_one")
        ledger.append(contentHash: "hash_two")
        ledger.append(contentHash: "hash_three")
        
        let verificationResult = ledger.verify()
        switch verificationResult {
        case .success:
            // 🎉 ✨ LEDGER MASTERPIECE COMPLETE!
            break
        case .failure(let error):
            Issue.record("💥 Ledger verification failed: \(error.localizedDescription)")
        }
    }
    
    @Test("🌩️ AnimaSeal - Empty Chain Verification")
    func testEmptyLedgerVerification() {
        // An empty ledger has no truth to verify...
        let ledger = AnimaLedger()
        let result = ledger.verify()
        
        if case .failure(let error) = result {
            #expect(error == .emptyChain)
        } else {
            Issue.record("💥 Empty ledger verification should have failed!")
        }
    }
    
    @Test("🌩️ AnimaSeal - Invalid Genesis Block")
    func testInvalidGenesisBlock() {
        // A ledger built on a foundation of sand...
        let badGenesisBlock = AnimaBlock(id: UUID(), contentHash: "genesis_content", previousSeal: "not_the_expected_genesis_previous_seal")
        let ledger = AnimaLedger(blocks: [badGenesisBlock])
        
        let result = ledger.verify()
        if case .failure(let error) = result {
            #expect(error == .invalidGenesis(expected: AnimaSeal.defaultGenesisPreviousSeal, actual: "not_the_expected_genesis_previous_seal"))
        } else {
            Issue.record("💥 Ledger with invalid genesis should have failed verification!")
        }
    }
    
    @Test("🌩️ AnimaSeal - Tampered Block Content")
    func testTamperedBlockContent() {
        // A malicious agent tries to rewrite history!
        var ledger = AnimaLedger()
        ledger.append(contentHash: "hash_one")
        let targetBlock = ledger.append(contentHash: "hash_two")
        ledger.append(contentHash: "hash_three")
        
        // Verify the original is valid
        if case .failure(let error) = ledger.verify() {
            Issue.record("Original ledger should be valid, but got error: \(error)")
        }
        
        // Tamper with the second block's content hash without updating the seal
        var tamperedBlocks = ledger.blocks
        tamperedBlocks[1] = AnimaBlock(
            id: targetBlock.id,
            contentHash: "tampered_hash_two", // altered content!
            previousSeal: targetBlock.previousSeal,
            seal: targetBlock.seal, // original seal!
            timestamp: targetBlock.timestamp
        )
        
        let tamperedLedger = AnimaLedger(blocks: tamperedBlocks)
        let result = tamperedLedger.verify()
        
        if case .failure(let error) = result {
            // It should detect invalid seal on block 1 (the second block)
            if case .invalidSeal(let index, let blockId, _, _) = error {
                #expect(index == 1)
                #expect(blockId == targetBlock.id)
            } else {
                Issue.record("💥 Expected .invalidSeal error, got \(error)")
            }
        } else {
            Issue.record("💥 Ledger with tampered content should have failed verification!")
        }
    }
    
    @Test("🌩️ AnimaSeal - Broken Ledger Link")
    func testBrokenLedgerLink() {
        // A block is inserted with a mismatched previousSeal!
        var ledger = AnimaLedger()
        ledger.append(contentHash: "hash_one")
        let secondBlock = ledger.append(contentHash: "hash_two")
        
        // Tamper with the second block's previousSeal
        var tamperedBlocks = ledger.blocks
        tamperedBlocks[1] = AnimaBlock(
            id: secondBlock.id,
            contentHash: secondBlock.contentHash,
            previousSeal: "broken_link_seal", // fake previous seal!
            seal: secondBlock.seal,
            timestamp: secondBlock.timestamp
        )
        
        let tamperedLedger = AnimaLedger(blocks: tamperedBlocks)
        let result = tamperedLedger.verify()
        
        if case .failure(let error) = result {
            if case .linkBroken(let index, let blockId, _, _) = error {
                #expect(index == 1)
                #expect(blockId == secondBlock.id)
            } else {
                Issue.record("💥 Expected .linkBroken error, got \(error)")
            }
        } else {
            Issue.record("💥 Ledger with broken link should have failed verification!")
        }
    }
}
