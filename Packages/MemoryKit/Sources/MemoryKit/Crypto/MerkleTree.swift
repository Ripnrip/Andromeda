/**
 * 🎭 The MerkleTree - The Spellbinding Guardian of Ledger Integrity
 *
 * "Through branches of cryptographic light, we bind the leaves of memory.
 * A single root of absolute truth, standing tall against the winds of tampering.
 * Every sibling whispers its secret, proving the whole without revealing all."
 *
 * - The Spellbinding Museum Director of Crypto
 */

import Foundation
import CryptoKit

/// 🌟 The MerkleTree - A cryptographic binary tree of memory blocks.
/// It aggregates leaves into a single root hash and generates verification proofs.
public struct MerkleTree: Sendable {
    /// 🎨 The leaves of our digital tree - the individual memory block hashes.
    public let leaves: [String]
    
    /// ✨ The levels of our cryptographic forest, from leaves (level 0) to root (last level).
    public let levels: [[String]]
    
    /// 👑 The crown jewel - the root hash of the Merkle Tree.
    public var root: String? {
        levels.last?.first
    }
    
    /// 🔮 Initialize a Merkle Tree from raw data blocks.
    /// - Parameter blocks: The array of data blocks to hash and tree-ify.
    public init(blocks: [Data]) {
        // 🧮 ✨ DATA ALCHEMY COMMENCES!
        let leafHashes = blocks.map { data in
            let digest = SHA256.hash(data: data)
            return digest.map { String(format: "%02x", $0) }.joined()
        }
        self.leaves = leafHashes
        self.levels = MerkleTree.buildLevels(leaves: leafHashes)
    }
    
    /// 🔮 Initialize a Merkle Tree from pre-computed leaf hashes.
    /// - Parameter leafHashes: The array of leaf hashes.
    public init(leafHashes: [String]) {
        self.leaves = leafHashes
        self.levels = MerkleTree.buildLevels(leaves: leafHashes)
    }
    
    /// 🌟 The Level Builder - Constructing the levels of our cryptographic pyramid.
    private static func buildLevels(leaves: [String]) -> [[String]] {
        guard !leaves.isEmpty else { return [] }
        var levels: [[String]] = [leaves]
        var currentLevel = leaves
        
        while currentLevel.count > 1 {
            var nextLevel: [String] = []
            for i in stride(from: 0, to: currentLevel.count, by: 2) {
                let left = currentLevel[i]
                let right = (i + 1 < currentLevel.count) ? currentLevel[i + 1] : left
                
                // Combine left and right hashes
                let combinedData = Data((left + right).utf8)
                let digest = SHA256.hash(data: combinedData)
                let parentHash = digest.map { String(format: "%02x", $0) }.joined()
                nextLevel.append(parentHash)
            }
            levels.append(nextLevel)
            currentLevel = nextLevel
        }
        
        return levels
    }
    
    /// 📜 Generate a Merkle proof for the leaf at the given index.
    /// - Parameter index: The index of the leaf.
    /// - Returns: A `MerkleProof` if index is valid, otherwise `nil`.
    public func makeProof(index: Int) -> MerkleProof? {
        guard index >= 0, index < leaves.count else { return nil }
        
        var siblings: [MerkleProof.Sibling] = []
        var currentIndex = index
        
        // Traverse up the levels, except the root level (which is the last level)
        for levelIndex in 0..<(levels.count - 1) {
            let currentLevel = levels[levelIndex]
            
            // Determine sibling index
            let isEven = (currentIndex % 2 == 0)
            let siblingIndex = isEven ? currentIndex + 1 : currentIndex - 1
            
            let siblingHash: String
            let isLeft: Bool
            
            if siblingIndex < currentLevel.count {
                siblingHash = currentLevel[siblingIndex]
                isLeft = !isEven
            } else {
                // If odd count at this level and currentIndex is the last element,
                // the sibling is itself (duplicated).
                siblingHash = currentLevel[currentIndex]
                isLeft = false
            }
            
            siblings.append(MerkleProof.Sibling(hash: siblingHash, isLeft: isLeft))
            currentIndex /= 2
        }
        
        return MerkleProof(leaf: leaves[index], index: index, siblings: siblings)
    }
}

/// 📜 The MerkleProof - A cryptographic passport to prove leaf membership.
public struct MerkleProof: Sendable, Codable, Equatable {
    /// 🌟 Sibling - A sibling node in the Merkle Tree path.
    public struct Sibling: Sendable, Codable, Equatable {
        public let hash: String
        public let isLeft: Bool
        
        public init(hash: String, isLeft: Bool) {
            self.hash = hash
            self.isLeft = isLeft
        }
    }
    
    public let leaf: String
    public let index: Int
    public let siblings: [Sibling]
    
    public init(leaf: String, index: Int, siblings: [Sibling]) {
        self.leaf = leaf
        self.index = index
        self.siblings = siblings
    }
    
    /// 🛡️ Verifies that this proof reconstructs the expected root hash.
    /// - Parameter expectedRoot: The root hash we expect to match.
    /// - Returns: `true` if the reconstructed root matches `expectedRoot`, otherwise `false`.
    public func verify(expectedRoot: String) -> Bool {
        var currentHash = leaf
        for sibling in siblings {
            let combinedData: Data
            if sibling.isLeft {
                combinedData = Data((sibling.hash + currentHash).utf8)
            } else {
                combinedData = Data((currentHash + sibling.hash).utf8)
            }
            let digest = SHA256.hash(data: combinedData)
            currentHash = digest.map { String(format: "%02x", $0) }.joined()
        }
        return currentHash == expectedRoot
    }
}
