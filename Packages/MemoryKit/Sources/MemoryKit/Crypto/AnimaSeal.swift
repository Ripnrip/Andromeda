/**
 * 🎭 The AnimaSeal - The Cryptographic Ledger Seal and Verification Engine
 *
 * "Each memory block is sealed, bound to the past by a thread of cryptographic steel.
 * To alter one is to break all. The chain remembers, the ledger endures,
 * and truth remains immutable on-device."
 *
 * - The Cosmic Process Orchestrator of Anima
 */

import Foundation
import CryptoKit

/// 🌟 The AnimaBlock - A cryptographically sealed block in the memory ledger.
public struct AnimaBlock: Sendable, Codable, Equatable {
    /// 🆔 Unique identifier for this block.
    public let id: UUID
    
    /// 💎 The hash of the block's content (e.g. narrative content).
    public let contentHash: String
    
    /// 🔗 The seal/hash of the preceding block in the ledger.
    public let previousSeal: String
    
    /// 🛡️ The cryptographic seal of this block, composed of its `contentHash` + `previousSeal`.
    public let seal: String
    
    /// ⏰ The timestamp when this block was sealed.
    public let timestamp: Date
    
    /// 🔮 Initialize a new Sealed Block, automatically computing its cryptographic seal.
    public init(id: UUID = UUID(), contentHash: String, previousSeal: String, timestamp: Date = Date()) {
        self.id = id
        self.contentHash = contentHash
        self.previousSeal = previousSeal
        self.timestamp = timestamp
        self.seal = AnimaBlock.computeSeal(contentHash: contentHash, previousSeal: previousSeal)
    }
    
    /// 🔮 Initialize a Sealed Block with an explicit seal (useful for decoding or simulating tampering).
    public init(id: UUID, contentHash: String, previousSeal: String, seal: String, timestamp: Date) {
        self.id = id
        self.contentHash = contentHash
        self.previousSeal = previousSeal
        self.seal = seal
        self.timestamp = timestamp
    }
    
    /// 🧮 Compute the cryptographic seal for a block.
    /// - Parameters:
    ///   - contentHash: The hash of the block's content.
    ///   - previousSeal: The seal of the preceding block.
    /// - Returns: A SHA-256 hex string seal.
    public static func computeSeal(contentHash: String, previousSeal: String) -> String {
        let combined = contentHash + previousSeal
        let digest = SHA256.hash(data: Data(combined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// 🛡️ The AnimaSeal - The verification engine that audits the ledger's integrity.
public struct AnimaSeal: Sendable {
    /// 🌩️ ValidationError - The creative challenges encountered during ledger verification.
    public enum ValidationError: Error, Equatable, LocalizedError {
        /// The ledger chain contains no blocks.
        case emptyChain
        
        /// The genesis block's previous seal did not match the expected genesis anchor.
        case invalidGenesis(expected: String, actual: String)
        
        /// A block's seal is invalid (does not match its recomputed seal).
        case invalidSeal(index: Int, blockId: UUID, expected: String, actual: String)
        
        /// The link between two blocks is broken (previousSeal of block does not match seal of prior block).
        case linkBroken(index: Int, blockId: UUID, expectedPreviousSeal: String, actualPreviousSeal: String)
        
        public var errorDescription: String? {
            switch self {
            case .emptyChain:
                return "🌩️ Verification halted: The ledger chain is completely empty."
            case .invalidGenesis(let expected, let actual):
                return "🌩️ Verification halted: Genesis block previous seal is invalid. Expected: \(expected), Actual: \(actual)."
            case .invalidSeal(let index, let blockId, let expected, let actual):
                return "🌩️ Verification halted: Block at index \(index) (ID: \(blockId)) has an invalid seal. Expected: \(expected), Actual: \(actual)."
            case .linkBroken(let index, let blockId, let expected, let actual):
                return "🌩️ Verification halted: Ledger link broken at index \(index) (ID: \(blockId)). Expected previous seal: \(expected), Actual: \(actual)."
            }
        }
    }
    
    /// 💎 The default genesis anchor seal (64 zeros).
    public static let defaultGenesisPreviousSeal = String(repeating: "0", count: 64)
    
    /// 🔍 Verify the integrity of a sequence of blocks.
    /// - Parameters:
    ///   - blocks: The array of sealed blocks to verify.
    ///   - genesisPreviousSeal: The expected previous seal for the genesis block.
    /// - Returns: A `Result` indicating success or a detailed `ValidationError` identifying where the chain was compromised.
    public static func verifyChain(_ blocks: [AnimaBlock], genesisPreviousSeal: String = defaultGenesisPreviousSeal) -> Result<Void, ValidationError> {
        guard !blocks.isEmpty else {
            return .failure(.emptyChain)
        }
        
        // Verify genesis block previous seal
        let genesis = blocks[0]
        if genesis.previousSeal != genesisPreviousSeal {
            return .failure(.invalidGenesis(expected: genesisPreviousSeal, actual: genesis.previousSeal))
        }
        
        var expectedPreviousSeal = genesisPreviousSeal
        
        for (index, block) in blocks.enumerated() {
            // Check that the block's previousSeal matches the expected previous seal (the seal of the prior block)
            if block.previousSeal != expectedPreviousSeal {
                return .failure(.linkBroken(
                    index: index,
                    blockId: block.id,
                    expectedPreviousSeal: expectedPreviousSeal,
                    actualPreviousSeal: block.previousSeal
                ))
            }
            
            // Recompute seal and verify it matches the block's seal
            let computedSeal = AnimaBlock.computeSeal(contentHash: block.contentHash, previousSeal: block.previousSeal)
            if block.seal != computedSeal {
                return .failure(.invalidSeal(
                    index: index,
                    blockId: block.id,
                    expected: computedSeal,
                    actual: block.seal
                ))
            }
            
            // Update expected previous seal for the next block
            expectedPreviousSeal = block.seal
        }
        
        return .success(())
    }
}

/// 📜 The AnimaLedger - An append-only, cryptographically sealed sequence of memory blocks.
public struct AnimaLedger: Sendable, Codable, Equatable {
    /// 🎪 The blocks currently residing in our ledger.
    public private(set) var blocks: [AnimaBlock]
    
    /// 💎 The genesis anchor seal.
    public let genesisPreviousSeal: String
    
    /// 👑 The latest seal in the ledger, or the genesis anchor if empty.
    public var latestSeal: String {
        blocks.last?.seal ?? genesisPreviousSeal
    }
    
    /// 🔮 Initialize an empty ledger.
    public init(genesisPreviousSeal: String = AnimaSeal.defaultGenesisPreviousSeal) {
        self.blocks = []
        self.genesisPreviousSeal = genesisPreviousSeal
    }
    
    /// 🔮 Initialize a ledger with pre-existing blocks.
    public init(blocks: [AnimaBlock], genesisPreviousSeal: String = AnimaSeal.defaultGenesisPreviousSeal) {
        self.blocks = blocks
        self.genesisPreviousSeal = genesisPreviousSeal
    }
    
    /// ➕ Append a new memory block to the ledger, sealing it cryptographically.
    /// - Parameters:
    ///   - contentHash: The hash of the block's content.
    ///   - id: Unique identifier for the block (defaults to a new UUID).
    ///   - timestamp: The timestamp when the block is appended (defaults to now).
    /// - Returns: The newly created and sealed `AnimaBlock`.
    @discardableResult
    public mutating func append(contentHash: String, id: UUID = UUID(), timestamp: Date = Date()) -> AnimaBlock {
        let previous = latestSeal
        let block = AnimaBlock(id: id, contentHash: contentHash, previousSeal: previous, timestamp: timestamp)
        blocks.append(block)
        return block
    }
    
    /// 🛡️ Verify the integrity of the entire ledger.
    /// - Returns: A `Result` indicating success or a detailed `AnimaSeal.ValidationError`.
    public func verify() -> Result<Void, AnimaSeal.ValidationError> {
        AnimaSeal.verifyChain(blocks, genesisPreviousSeal: genesisPreviousSeal)
    }
}
