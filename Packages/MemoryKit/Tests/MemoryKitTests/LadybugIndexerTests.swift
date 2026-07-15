import Foundation
import Testing
import OSLog
@testable import MemoryKit

/**
 * 🎭 The LadybugIndexerTests - The Quality Assurance Ritual of the Cartographer
 *
 * "We mock the endpoints, we sever the wires,
 * and we watch as our resilient scribe walks through the fire.
 * No dropped packet shall break our stride;
 * the indexer stands tall, with graceful fail-open pride."
 *
 * - The Spellbinding Museum Director of Quality Assurance
 */

// MARK: - Mock URL Protocol

/// 🌐 The MockURLProtocol - Intercepting network request portals
class MockURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var handlers: [Int: @Sendable (URLRequest) throws -> (HTTPURLResponse, Data?)] = [:]
    
    static func register(port: Int, handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data?)) {
        lock.lock()
        defer { lock.unlock() }
        handlers[port] = handler
    }
    
    static func unregister(port: Int) {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeValue(forKey: port)
    }
    
    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        guard let port = request.url?.port else {
            let creativeChallenge = NSError(
                domain: "MockURLProtocol",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "No port found in the request URL"]
            )
            client?.urlProtocol(self, didFailWithError: creativeChallenge)
            return
        }
        
        MockURLProtocol.lock.lock()
        let handler = MockURLProtocol.handlers[port]
        MockURLProtocol.lock.unlock()
        
        guard let handler = handler else {
            let creativeChallenge = NSError(
                domain: "MockURLProtocol",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "No handler registered for port \(port)"]
            )
            client?.urlProtocol(self, didFailWithError: creativeChallenge)
            return
        }
        
        do {
            let (response, mysticalData) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let mysticalData = mysticalData {
                client?.urlProtocol(self, didLoad: mysticalData)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    
    override func stopLoading() {}
}

// MARK: - Test Suite

@Suite("LadybugIndexer Tests 🐞🧪")
struct LadybugIndexerTests {
    
    // 🌟 Helper to create a mock URLSession
    private func makeMockSession() -> URLSession {
        let cosmicConfiguration = URLSessionConfiguration.ephemeral
        cosmicConfiguration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: cosmicConfiguration)
    }
    
    // 🌟 The Deterministic Key Test - Proving our UUID mapping magic
    @Test("Test deterministic UUID generation 🪄")
    func testDeterministicUUID() {
        // 🎨 Given some raw wisdom hashes
        let hash1 = "sha256:12345"
        let hash2 = "sha256:12345"
        let hash3 = "sha256:67890"
        
        // ✨ When we map them to UUID space
        let uuid1 = UUID.deterministic(from: hash1)
        let uuid2 = UUID.deterministic(from: hash2)
        let uuid3 = UUID.deterministic(from: hash3)
        
        // 🎉 Then they must be perfectly stable and distinct
        #expect(uuid1 == uuid2, "Identical hashes must produce identical UUIDs! The universe demands symmetry. 🌌")
        #expect(uuid1 != uuid3, "Different hashes must produce different UUIDs! No identity theft in our constellation. 🕵️‍♂️")
    }
    
    // 🌟 The Node Alchemy Success Test - Proving happy path node indexing
    @Test("Test successful node indexing 🌟")
    func testIndexNodeSuccess() async throws {
        let port = 18286
        let mockSession = makeMockSession()
        let indexer = LadybugIndexer(baseURL: URL(string: "http://127.0.0.1:\(port)")!, session: mockSession)
        
        let pointId = UUID.deterministic(from: "sha256:abc")
        let payload = LadybugNode.Payload(
            contentHash: "sha256:abc",
            visibility: "public",
            project: "multibrain",
            date: "2026-07-14",
            tags: ["insight/discovery"],
            sourcePath: "07-Sessions/2026-07-14--multibrain--codex.md"
        )
        let node = LadybugNode(pointId: pointId, vector: Array(repeating: 0.1, count: 384), payload: payload)
        
        MockURLProtocol.register(port: port) { request in
            #expect(request.url?.path == "/nodes", "Request must target the /nodes portal!")
            #expect(request.httpMethod == "POST", "Request must use POST method!")
            
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, nil)
        }
        defer { MockURLProtocol.unregister(port: port) }
        
        // ✨ When we index the node
        let success = await indexer.indexNode(node)
        let isDirty = await indexer.isDirty
        
        // 🎉 Then it must succeed and keep the index clean
        #expect(success, "Node indexing should succeed under clear skies! ☀️")
        #expect(!isDirty, "The index must remain pristine and clean! 🧹")
    }
    
    // 🌟 The Connection Weaving Success Test - Proving happy path connection indexing
    @Test("Test successful connection indexing 🕸️")
    func testIndexConnectionSuccess() async throws {
        let port = 18287
        let mockSession = makeMockSession()
        let indexer = LadybugIndexer(baseURL: URL(string: "http://127.0.0.1:\(port)")!, session: mockSession)
        
        let connection = LadybugConnection(
            fromId: UUID.deterministic(from: "sha256:abc"),
            toId: UUID.deterministic(from: "sha256:def"),
            type: "SHARES_PROJECT"
        )
        
        MockURLProtocol.register(port: port) { request in
            #expect(request.url?.path == "/edges", "Request must target the /edges portal!")
            #expect(request.httpMethod == "POST", "Request must use POST method!")
            
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 201,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, nil)
        }
        defer { MockURLProtocol.unregister(port: port) }
        
        // ✨ When we index the connection
        let success = await indexer.indexConnection(connection)
        let isDirty = await indexer.isDirty
        
        // 🎉 Then it must succeed and keep the index clean
        #expect(success, "Connection indexing should succeed when the threads align! 🧵")
        #expect(!isDirty, "The index must remain pristine and clean! 🧹")
    }
    
    // 🌟 The Resilient Node Alchemy Test - Proving fail-open node indexing under network storm
    @Test("Test node indexing under network storm (Fail-Open) 🌩️")
    func testIndexNodeNetworkFailure() async throws {
        let port = 18288
        let mockSession = makeMockSession()
        let indexer = LadybugIndexer(baseURL: URL(string: "http://127.0.0.1:\(port)")!, session: mockSession)
        
        let pointId = UUID.deterministic(from: "sha256:abc")
        let payload = LadybugNode.Payload(
            contentHash: "sha256:abc",
            visibility: "private",
            project: "multibrain",
            date: "2026-07-14",
            tags: ["gotcha"],
            sourcePath: "07-Sessions/2026-07-14--multibrain--codex.md"
        )
        let node = LadybugNode(pointId: pointId, vector: Array(repeating: 0.2, count: 384), payload: payload)
        
        MockURLProtocol.register(port: port) { _ in
            throw URLError(.notConnectedToInternet)
        }
        defer { MockURLProtocol.unregister(port: port) }
        
        // ✨ When we attempt node indexing during a storm
        let success = await indexer.indexNode(node)
        let isDirty = await indexer.isDirty
        
        // 🎉 Then it must degrade gracefully (return false, NOT throw/halt, and mark dirty)
        #expect(!success, "Node indexing must report failure when the internet is asleep! 💤")
        #expect(isDirty, "The index must be marked dirty to flag a future repair ritual! 🛠️")
    }
    
    // 🌟 The Resilient Connection Weaving Test - Proving fail-open connection indexing under network storm
    @Test("Test connection indexing under network storm (Fail-Open) 🌩️")
    func testIndexConnectionNetworkFailure() async throws {
        let port = 18289
        let mockSession = makeMockSession()
        let indexer = LadybugIndexer(baseURL: URL(string: "http://127.0.0.1:\(port)")!, session: mockSession)
        
        let connection = LadybugConnection(
            fromId: UUID.deterministic(from: "sha256:abc"),
            toId: UUID.deterministic(from: "sha256:def"),
            type: "SHARES_CONCEPT",
            concept: "gotcha"
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
        
        // ✨ When we attempt connection indexing during a storm
        let success = await indexer.indexConnection(connection)
        let isDirty = await indexer.isDirty
        
        // 🎉 Then it must degrade gracefully (return false, NOT throw/halt, and mark dirty)
        #expect(!success, "Connection indexing must report failure when the server is grumpy! 🌩️")
        #expect(isDirty, "The index must be marked dirty to flag a future repair ritual! 🛠️")
    }
    
    // 🌟 The High-Level Ingestion Test - Proving end-to-end convenience methods
    @Test("Test high-level index and connect convenience methods 🚀")
    func testHighLevelConvenienceMethods() async throws {
        let port = 18290
        let mockSession = makeMockSession()
        let indexer = LadybugIndexer(baseURL: URL(string: "http://127.0.0.1:\(port)")!, session: mockSession)
        
        MockURLProtocol.register(port: port) { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, nil)
        }
        defer { MockURLProtocol.unregister(port: port) }
        
        // ✨ When we use high-level index convenience method
        let nodeSuccess = await indexer.index(
            contentHash: "sha256:highlevel",
            vector: Array(repeating: 0.5, count: 384),
            visibility: "internal",
            project: "Anima",
            date: "2026-07-14",
            tags: ["pattern"],
            sourcePath: "07-Sessions/2026-07-14--Anima--claude.md"
        )
        
        // ✨ And high-level connect convenience method
        let connectSuccess = await indexer.connect(
            fromHash: "sha256:highlevel",
            toHash: "sha256:target",
            type: "SHARES_CONCEPT",
            concept: "pattern"
        )
        
        // 🎉 Then both must succeed beautifully
        #expect(nodeSuccess, "High-level node ingestion must be smooth and majestic! 🦅")
        #expect(connectSuccess, "High-level connection weaving must be strong and secure! 💪")
    }
    
    // 🌟 The Purification Test - Proving dirty flag reset
    @Test("Test dirty state purification 💎")
    func testResetDirty() async throws {
        let port = 18291
        let mockSession = makeMockSession()
        let indexer = LadybugIndexer(baseURL: URL(string: "http://127.0.0.1:\(port)")!, session: mockSession)
        
        MockURLProtocol.register(port: port) { _ in
            throw URLError(.timedOut)
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
        #expect(initiallyDirty, "The index must be dirty after a timed out request! 🌩️")
        
        // ✨ When we perform the purification ritual
        await indexer.resetDirty()
        let purifiedDirty = await indexer.isDirty
        
        // 🎉 Then it must be clean once more
        #expect(!purifiedDirty, "The purification ritual must restore the index to a clean state! 💎")
    }
}
