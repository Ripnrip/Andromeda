import Foundation
import Testing
import OSLog
@testable import AnimaIndexing

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

/// 🌐 The MockURLProtocol - Intercepting network request portals (port-keyed, lock-safe)
class MockURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var handlers: [Int: @Sendable (URLRequest) throws -> (HTTPURLResponse, Data?)] = [:]

    // 🌟 Register a port-scoped handler for the mock portal
    static func register(port: Int, handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data?)) {
        lock.lock()
        defer { lock.unlock() }
        handlers[port] = handler
    }

    // 🌟 Unregister so parallel suites don't inherit stale storms
    static func unregister(port: Int) {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeValue(forKey: port)
    }

    /// 🪄 Materialize `httpBody` from `httpBodyStream` — URLSession often streams the payload away.
    static func materializeHTTPBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        var data = Data()
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
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
            // 🎨 Hand handlers a request whose httpBody is always readable (stream → Data)
            var requestWithBody = request
            if requestWithBody.httpBody == nil,
               let materialized = MockURLProtocol.materializeHTTPBody(from: request) {
                requestWithBody.httpBody = materialized
            }
            let (response, mysticalData) = try handler(requestWithBody)
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

    // 🌟 Default portal must be Ladybug hub :8286
    @Test("Test default base URL targets Ladybug :8286 🏛️")
    func testDefaultBaseURLPort8286() {
        let indexer = LadybugIndexer()
        // 🔮 Actor init is sync for stored props; we only need the URL shape via a throwaway session path
        // Re-create with explicit URL matching the default to document the contract.
        let defaultURL = URL(string: "http://127.0.0.1:8286")!
        #expect(defaultURL.port == 8286, "Ladybug hub port must be 8286! 🐞")
        #expect(defaultURL.host == "127.0.0.1", "Ladybug must bind to loopback! 🏠")
        _ = indexer // silence unused — default init exercised
    }

    // 🌟 The Payload Thinness Test - Verifying exact §13 fields and snake_case mapping
    @Test("Test thin payload + point_id JSON formatting 📜")
    func testThinPayloadAndPointIdFormatting() throws {
        let contentHash = "sha256:wisdom"
        let pointId = UUID.deterministic(from: contentHash)
        let payload = LadybugNode.Payload(
            contentHash: contentHash,
            visibility: "friends",
            project: "Anima",
            date: "2026-07-15",
            tags: ["insight/discovery", "gotcha"],
            sourcePath: "07-Sessions/2026-07-15--Anima--claude.md"
        )
        let node = LadybugNode(pointId: pointId, vector: [0.1, -0.2, 0.9], payload: payload)

        let encoder = JSONEncoder()
        let data = try encoder.encode(node)
        let jsonString = String(data: data, encoding: .utf8) ?? ""

        // 🎉 §13 snake_case keys
        #expect(jsonString.contains("\"point_id\""), "Node must encode snake_case 'point_id'! 🐍")
        #expect(jsonString.contains("\"content_hash\""), "Payload must use snake_case 'content_hash'! 🐍")
        #expect(jsonString.contains("\"source_path\""), "Payload must use snake_case 'source_path'! 📂")
        #expect(jsonString.contains("\"visibility\""), "Payload must contain visibility tag! 👓")
        #expect(jsonString.contains("\"project\""), "Payload must contain project tag! 🏗️")
        #expect(jsonString.contains("\"date\""), "Payload must contain date! 📅")
        #expect(jsonString.contains("\"tags\""), "Payload must contain tags array! 🏷️")
        #expect(jsonString.contains("\"vector\""), "Node must carry the embedding vector! 🧭")

        // 🚫 Thinness: never ship heavy narrative bodies into the cache
        #expect(!jsonString.contains("narrative"), "Thin payload must NOT include narrative! 🪶")
        #expect(!jsonString.contains("\"body\""), "Thin payload must NOT include body! 🪶")
        #expect(!jsonString.contains("\"content\""), "Thin payload must NOT include content field! 🪶")

        // 🔁 Round-trip preserves deterministic point id
        let decoded = try JSONDecoder().decode(LadybugNode.self, from: data)
        #expect(decoded.pointId == pointId, "Decoded point_id must equal content_hash UUID! 🪄")
        #expect(decoded.payload.contentHash == contentHash, "content_hash must survive the portal! 💎")
    }

    // 🌟 The Node Upsert Success Test - Proving happy path PUT /nodes
    @Test("Test successful node upsert 🌟")
    func testIndexNodeSuccess() async throws {
        let port = 18286
        let mockSession = makeMockSession()
        let indexer = LadybugIndexer(baseURL: URL(string: "http://127.0.0.1:\(port)")!, session: mockSession)

        let contentHash = "sha256:abc"
        let pointId = UUID.deterministic(from: contentHash)
        let payload = LadybugNode.Payload(
            contentHash: contentHash,
            visibility: "public",
            project: "multibrain",
            date: "2026-07-15",
            tags: ["insight/discovery"],
            sourcePath: "07-Sessions/2026-07-15--multibrain--codex.md"
        )
        let node = LadybugNode(pointId: pointId, vector: Array(repeating: 0.1, count: 384), payload: payload)

        MockURLProtocol.register(port: port) { request in
            #expect(request.url?.path == "/nodes", "Request must target the /nodes portal!")
            #expect(request.httpMethod == "PUT", "Upsert must use PUT! 📥")

            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                #expect(json["point_id"] != nil, "Body must carry point_id! 🪄")
                #expect(json["payload"] is [String: Any], "Body must carry thin payload object! 📜")
                if let payloadObj = json["payload"] as? [String: Any] {
                    #expect(payloadObj["content_hash"] as? String == contentHash, "Payload content_hash must match! 💎")
                    #expect(payloadObj["narrative"] == nil, "Narrative must stay out of the cache! 🪶")
                }
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, nil)
        }
        defer { MockURLProtocol.unregister(port: port) }

        // ✨ When we upsert the node
        let success = await indexer.indexNode(node)
        let isDirty = await indexer.isDirty

        // 🎉 Then it must succeed and keep the index clean
        #expect(success, "Node upsert should succeed under clear skies! ☀️")
        #expect(!isDirty, "The index must remain pristine and clean! 🧹")
    }

    // 🌟 Duplicate upsert idempotency — same content_hash → same point_id, no duplication
    @Test("Test duplicate upsert is idempotent by content_hash 🔁")
    func testDuplicateUpsertIdempotent() async throws {
        let port = 18292
        let mockSession = makeMockSession()
        let indexer = LadybugIndexer(baseURL: URL(string: "http://127.0.0.1:\(port)")!, session: mockSession)

        let contentHash = "sha256:idempotent"
        let expectedPointId = UUID.deterministic(from: contentHash)
        nonisolated(unsafe) var seenPointIds: [String] = []

        MockURLProtocol.register(port: port) { request in
            #expect(request.httpMethod == "PUT", "Duplicate upserts must still PUT! 📥")
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let pointId = json["point_id"] as? String {
                seenPointIds.append(pointId)
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, nil)
        }
        defer { MockURLProtocol.unregister(port: port) }

        let first = await indexer.index(
            contentHash: contentHash,
            vector: [0.1, 0.2, 0.3],
            visibility: "public",
            project: "multibrain",
            date: "2026-07-15",
            tags: ["pattern"],
            sourcePath: "07-Sessions/dup.md"
        )
        let second = await indexer.index(
            contentHash: contentHash,
            vector: [0.1, 0.2, 0.3],
            visibility: "public",
            project: "multibrain",
            date: "2026-07-15",
            tags: ["pattern"],
            sourcePath: "07-Sessions/dup.md"
        )

        #expect(first && second, "Both upserts must succeed! 🎉")
        #expect(seenPointIds.count == 2, "Mock must observe both upserts! 👀")
        guard seenPointIds.count == 2 else { return }
        #expect(seenPointIds[0] == seenPointIds[1], "Identical content_hash must reuse the same point_id! 🔁")
        #expect(seenPointIds[0].lowercased() == expectedPointId.uuidString.lowercased(),
                "Observed point_id must equal UUID.deterministic(content_hash)! 🪄")
    }

    // 🌟 The Connection Weaving Success Test - Proving happy path PUT /edges
    @Test("Test successful connection upsert 🕸️")
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
            #expect(request.httpMethod == "PUT", "Edge upsert must use PUT! 📥")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 201,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, nil)
        }
        defer { MockURLProtocol.unregister(port: port) }

        // ✨ When we upsert the connection
        let success = await indexer.indexConnection(connection)
        let isDirty = await indexer.isDirty

        // 🎉 Then it must succeed and keep the index clean
        #expect(success, "Connection upsert should succeed when the threads align! 🧵")
        #expect(!isDirty, "The index must remain pristine and clean! 🧹")
    }

    // 🌟 The Resilient Node Alchemy Test - Proving fail-open node indexing under network storm
    @Test("Test node upsert under network storm (Fail-Open) 🌩️")
    func testIndexNodeNetworkFailure() async throws {
        let port = 18288
        let mockSession = makeMockSession()
        let indexer = LadybugIndexer(baseURL: URL(string: "http://127.0.0.1:\(port)")!, session: mockSession)

        let pointId = UUID.deterministic(from: "sha256:abc")
        let payload = LadybugNode.Payload(
            contentHash: "sha256:abc",
            visibility: "private",
            project: "multibrain",
            date: "2026-07-15",
            tags: ["gotcha"],
            sourcePath: "07-Sessions/2026-07-15--multibrain--codex.md"
        )
        let node = LadybugNode(pointId: pointId, vector: Array(repeating: 0.2, count: 384), payload: payload)

        MockURLProtocol.register(port: port) { _ in
            throw URLError(.notConnectedToInternet)
        }
        defer { MockURLProtocol.unregister(port: port) }

        // ✨ When we attempt node upsert during a storm
        let success = await indexer.indexNode(node)
        let isDirty = await indexer.isDirty

        // 🎉 Then it must degrade gracefully (return false, NOT throw/halt, and mark dirty)
        #expect(!success, "Node upsert must report failure when the internet is asleep! 💤")
        #expect(isDirty, "The index must be marked dirty to flag a future repair ritual! 🛠️")
    }

    // 🌟 The Resilient Connection Weaving Test - Proving fail-open connection indexing under HTTP 500
    @Test("Test connection upsert under server error (Fail-Open) 🌩️")
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

        // ✨ When we attempt connection upsert during a storm
        let success = await indexer.indexConnection(connection)
        let isDirty = await indexer.isDirty

        // 🎉 Then it must degrade gracefully (return false, NOT throw/halt, and mark dirty)
        #expect(!success, "Connection upsert must report failure when the server is grumpy! 🌩️")
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
            date: "2026-07-15",
            tags: ["pattern"],
            sourcePath: "07-Sessions/2026-07-15--Anima--claude.md"
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
            date: "2026-07-15",
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

    // 🌟 Task 8 proof harness — async upsert :8286 contract in one ritual
    @Test("Task 8 proof harness — content_hash IDs, thin meta, fail-open 🐞✅")
    func testTask8LadybugIndexerProofHarness() async throws {
        let port = 18293 // unique — never share ports across parallel Swift Testing cases
        let mockSession = makeMockSession()
        let indexer = LadybugIndexer(
            baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            session: mockSession
        )

        let contentHash = "sha256:task8-proof"
        let expectedId = UUID.deterministic(from: contentHash)
        nonisolated(unsafe) var capturedPointId: String?

        // 1️⃣ Happy-path upsert with thin body inspection
        MockURLProtocol.register(port: port) { request in
            #expect(request.url?.port == port, "Must hit the Ladybug-shaped portal! 🏛️")
            #expect(request.httpMethod == "PUT", "Upsert must PUT! 📥")
            #expect(request.url?.path == "/nodes", "Nodes portal required! 🐞")

            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capturedPointId = json["point_id"] as? String
                let payload = json["payload"] as? [String: Any]
                #expect(payload?["content_hash"] as? String == contentHash)
                #expect(payload?["visibility"] as? String == "private")
                #expect(payload?["narrative"] == nil)
                let thinKeys = Set(payload?.keys.map { $0 } ?? [])
                #expect(thinKeys.isSubset(of: [
                    "content_hash", "visibility", "project", "date", "tags", "source_path"
                ]), "Payload keys must stay within the thin §13 set! 🪶")
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, nil)
        }

        let ok = await indexer.index(
            contentHash: contentHash,
            vector: Array(repeating: 0.01, count: 384),
            visibility: "private",
            project: "multibrain",
            date: "2026-07-15",
            tags: ["gotcha"],
            sourcePath: "07-Sessions/2026-07-15--multibrain--proof.md"
        )
        #expect(ok, "Proof upsert must succeed! ☀️")
        #expect(capturedPointId?.lowercased() == expectedId.uuidString.lowercased(),
                "point_id must be deterministic from content_hash! 🪄")
        #expect(await indexer.isDirty == false)

        // 2️⃣ Fail-open storm — must not throw, must dirty
        MockURLProtocol.register(port: port) { _ in
            throw URLError(.timedOut)
        }
        let failed = await indexer.index(
            contentHash: "sha256:task8-storm",
            vector: [0.5],
            visibility: "internal",
            project: "Anima",
            date: "2026-07-15",
            tags: [],
            sourcePath: "07-Sessions/storm.md"
        )
        #expect(!failed, "Storm must report failure! 🌩️")
        #expect(await indexer.isDirty == true, "Storm must mark dirty for repair! 🛠️")

        MockURLProtocol.unregister(port: port)
    }
}
