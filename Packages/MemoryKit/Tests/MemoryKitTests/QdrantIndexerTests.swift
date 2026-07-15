import Foundation
import Testing
import OSLog
@testable import MemoryKit

/**
 * 🎭 The QdrantIndexerTests - The Quality Assurance Ritual of the Vector Scribe
 *
 * "We sever the connections, we bend the dimensions,
 * we verify the sacred math of our coordinates,
 * and we test the resilience of our silent, fail-open scribe.
 * Let the tests run, and let the truth shine clear!"
 *
 * - The Spellbinding Museum Director of Quality Assurance
 */

// MARK: - Test Suite

@Suite("QdrantIndexer Tests 🕵️‍♂️🧪")
struct QdrantIndexerTests {
    
    // 🌟 Helper to create a mock URLSession
    private func makeMockSession() -> URLSession {
        let cosmicConfiguration = URLSessionConfiguration.ephemeral
        cosmicConfiguration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: cosmicConfiguration)
    }
    
    // 🌟 The Deterministic Key Test - Proving our UUIDv5 mapping magic
    @Test("Test deterministic UUIDv5 generation 🪄")
    func testDeterministicUUIDv5() {
        // 🎨 Given some raw wisdom hashes
        let hash1 = "sha256:abc"
        let hash2 = "sha256:abc"
        let hash3 = "sha256:xyz"
        
        // ✨ When we map them to UUIDv5 space
        let uuid1 = UUID.deterministicV5(from: hash1)
        let uuid2 = UUID.deterministicV5(from: hash2)
        let uuid3 = UUID.deterministicV5(from: hash3)
        
        // 🎉 Then they must be perfectly stable and distinct
        #expect(uuid1 == uuid2, "Identical content hashes must produce identical UUIDv5 points! Symmetrical magic. 🌌")
        #expect(uuid1 != uuid3, "Different content hashes must produce different UUIDv5 points! No cloning. 🕵️‍♂️")
        
        // 🔍 Asserting RFC 4122 compliance for UUIDv5 (version 5, variant 1)
        let uuidString = uuid1.uuidString.lowercased()
        
        // Version 5 (character 14 of lowercase string representation must be '5')
        let versionChar = uuidString[uuidString.index(uuidString.startIndex, offsetBy: 14)]
        #expect(versionChar == "5", "UUIDv5 must carry version character '5' at index 14! 🔮")
        
        // Variant RFC 4122 (character 19 of lowercase string must be '8', '9', 'a', or 'b')
        let variantChar = uuidString[uuidString.index(uuidString.startIndex, offsetBy: 19)]
        #expect(["8", "9", "a", "b"].contains(String(variantChar)), "UUIDv5 variant character at index 19 must be one of [8, 9, a, b]! 🎭")
    }
    
    // 🌟 The Vector Representation Test - Proving we can serialize both flat and named vectors
    @Test("Test vector JSON serialization formats 🧮")
    func testVectorSerialization() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        // 1. Flat Vector
        let flatVector = QdrantVector.flat([0.1, -0.2, 0.9])
        let flatData = try encoder.encode(flatVector)
        let decodedFlat = try decoder.decode(QdrantVector.self, from: flatData)
        
        #expect(decodedFlat == flatVector, "Flat vector must encode and decode perfectly! 📏")
        let flatString = String(data: flatData, encoding: .utf8) ?? ""
        #expect(flatString == "[0.1,-0.2,0.9]", "Flat vector JSON must be a raw float array! 🎨")
        
        // 2. Named Vector
        let namedVector = QdrantVector.named(["fast-all-minilm-l6-v2": [0.1, -0.2, 0.9]])
        let namedData = try encoder.encode(namedVector)
        let decodedNamed = try decoder.decode(QdrantVector.self, from: namedData)
        
        #expect(decodedNamed == namedVector, "Named vector must encode and decode perfectly! 🧭")
        let namedString = String(data: namedData, encoding: .utf8) ?? ""
        #expect(namedString.contains("fast-all-minilm-l6-v2"), "Named vector JSON must include the vector label! 🌌")
    }
    
    // 🌟 The Payload Thinness Test - Verifying exact fields and snake_case mapping
    @Test("Test thin payload formatting 📜")
    func testThinPayloadFormatting() throws {
        let payload = QdrantPayload(
            contentHash: "sha256:wisdom",
            visibility: "friends",
            project: "Anima",
            date: "2026-07-14",
            tags: ["insight/discovery", "gotcha"],
            sourcePath: "07-Sessions/2026-07-14--Anima--claude.md"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(payload)
        let jsonString = String(data: data, encoding: .utf8) ?? ""
        
        // 🎉 Verifying snake_case key mappings from docs/DATA-CONTRACTS.md §13
        #expect(jsonString.contains("\"content_hash\""), "Payload must use snake_case 'content_hash'! 🐍")
        #expect(jsonString.contains("\"source_path\""), "Payload must use snake_case 'source_path'! 📂")
        #expect(jsonString.contains("\"visibility\""), "Payload must contain visibility tag! 👓")
        #expect(jsonString.contains("\"project\""), "Payload must contain project tag! 🏗️")
        #expect(jsonString.contains("\"date\""), "Payload must contain date! 📅")
        #expect(jsonString.contains("\"tags\""), "Payload must contain tags array! 🏷️")
    }
    
    // 🌟 The Point Alchemy Success Test - Proving happy path point indexing with named vector
    @Test("Test successful point indexing to Qdrant 🌟")
    func testIndexPointSuccess() async throws {
        let port = 16333
        let mockSession = makeMockSession()
        let indexer = QdrantIndexer(
            baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            collectionName: "secondbrain_learnings",
            vectorName: "fast-all-minilm-l6-v2",
            session: mockSession
        )
        
        MockURLProtocol.register(port: port) { request in
            #expect(request.url?.path == "/collections/secondbrain_learnings/points", "Request must target points portal! 🌐")
            #expect(request.url?.query?.contains("wait=true") == true, "Request must specify wait=true query! ⏱️")
            #expect(request.httpMethod == "PUT", "Qdrant REST point upsert expects PUT method! 📥")
            
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, nil)
        }
        defer { MockURLProtocol.unregister(port: port) }
        
        // ✨ When we index high-level record
        let success = await indexer.index(
            contentHash: "sha256:abc",
            vector: [0.1, 0.2, 0.3],
            visibility: "public",
            project: "multibrain",
            date: "2026-07-14",
            tags: ["insight/discovery"],
            sourcePath: "07-Sessions/2026-07-14--multibrain--codex.md"
        )
        
        let isDirty = await indexer.isDirty
        
        // 🎉 Then it must succeed and keep the index clean
        #expect(success, "Vector indexing should succeed under serene skies! ☀️")
        #expect(!isDirty, "The indexer state must remain clean and pristine! 🧹")
    }
    
    // 🌟 The Resilient Point Ingestion Test - Proving fail-open behavior under network storm
    @Test("Test point indexing under network storm (Fail-Open) 🌩️")
    func testIndexPointNetworkFailure() async throws {
        let port = 16334
        let mockSession = makeMockSession()
        let indexer = QdrantIndexer(
            baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            collectionName: "secondbrain_learnings",
            vectorName: "fast-all-minilm-l6-v2",
            session: mockSession
        )
        
        MockURLProtocol.register(port: port) { _ in
            throw URLError(.timedOut)
        }
        defer { MockURLProtocol.unregister(port: port) }
        
        // ✨ When we attempt indexing during a storm
        let success = await indexer.index(
            contentHash: "sha256:abc",
            vector: [0.1, 0.2, 0.3],
            visibility: "private",
            project: "multibrain",
            date: "2026-07-14",
            tags: ["gotcha"],
            sourcePath: "07-Sessions/2026-07-14--multibrain--codex.md"
        )
        
        let isDirty = await indexer.isDirty
        
        // 🎉 Then it must fail-open gracefully (return false, NOT throw, and mark index dirty)
        #expect(!success, "Indexing should report failure when the server is unreachable! 🌩️")
        #expect(isDirty, "The index must be marked dirty to flag a future repair ritual! 🛠️")
    }
    
    // 🌟 The Resilient HTTP 500 Test - Proving fail-open behavior on server error
    @Test("Test point indexing on server error (Fail-Open) 🌧️")
    func testIndexPointServerError() async throws {
        let port = 16335
        let mockSession = makeMockSession()
        let indexer = QdrantIndexer(
            baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            collectionName: "secondbrain_learnings",
            vectorName: nil, // Test flat unnamed vector
            session: mockSession
        )
        
        MockURLProtocol.register(port: port) { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, nil)
        }
        defer { MockURLProtocol.unregister(port: port) }
        
        // ✨ When we attempt indexing with flat vector
        let success = await indexer.index(
            contentHash: "sha256:flat",
            vector: [0.5, 0.5, 0.5],
            visibility: "internal",
            project: "Anima",
            date: "2026-07-14",
            tags: ["pattern"],
            sourcePath: "07-Sessions/2026-07-14--Anima--claude.md"
        )
        
        let isDirty = await indexer.isDirty
        
        // 🎉 Then it must fail-open gracefully (return false, NOT throw, and mark index dirty)
        #expect(!success, "Indexing must report failure when the server is throwing storms! ⛈️")
        #expect(isDirty, "The index must be marked dirty! 🛠️")
    }
    
    // 🌟 The Purification Test - Proving dirty flag reset
    @Test("Test dirty state purification 💎")
    func testResetDirty() async throws {
        let port = 16336
        let mockSession = makeMockSession()
        let indexer = QdrantIndexer(
            baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            collectionName: "secondbrain_learnings",
            vectorName: "fast-all-minilm-l6-v2",
            session: mockSession
        )
        
        MockURLProtocol.register(port: port) { _ in
            throw URLError(.notConnectedToInternet)
        }
        defer { MockURLProtocol.unregister(port: port) }
        
        _ = await indexer.index(
            contentHash: "sha256:dirty",
            vector: [],
            visibility: "public",
            project: "Anima",
            date: "2026-07-14",
            tags: [],
            sourcePath: ""
        )
        
        let initiallyDirty = await indexer.isDirty
        #expect(initiallyDirty, "The index must be dirty after a failed connection! 🌩️")
        
        // ✨ When we perform the purification ritual
        await indexer.resetDirty()
        let purifiedDirty = await indexer.isDirty
        
        // 🎉 Then it must be clean once more
        #expect(!purifiedDirty, "The purification ritual must restore the index to a clean state! 💎")
    }
}
