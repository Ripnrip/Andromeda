import Foundation
import Testing
@testable import AnimaIndexing

/**
 * 🎭 The QdrantIndexerTests - The Quality Assurance Ritual of the Vector Scribe
 *
 * "We sever the connections, we bend the dimensions,
 * we verify the sacred math of our coordinates,
 * and we test the resilience of our silent, fail-open scribe.
 * Let the tests run, and let the truth shine clear!"
 *
 * - The Spellbinding Museum Director of Quality Assurance
 *
 * Spec: docs/DATA-CONTRACTS.md §13
 */

// MARK: - Mock URL Protocol (Qdrant-owned, no Ladybug coupling)

/// 🌐 The QdrantMockURLProtocol - Intercepting Qdrant REST portals without sharing Ladybug's mock.
final class QdrantMockURLProtocol: URLProtocol {
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

    /// 📦 Materialize httpBody even when URLSession stuffed it into a stream.
    static func requestBodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read > 0 {
                data.append(buffer, count: read)
            } else {
                break
            }
        }
        return data
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let port = request.url?.port else {
            client?.urlProtocol(self, didFailWithError: NSError(
                domain: "QdrantMockURLProtocol",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "No port found in the request URL"]
            ))
            return
        }

        Self.lock.lock()
        let handler = Self.handlers[port]
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: NSError(
                domain: "QdrantMockURLProtocol",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "No handler registered for port \(port)"]
            ))
            return
        }

        do {
            let (response, mysticalData) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let mysticalData {
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

@Suite("QdrantIndexer Tests 🕵️‍♂️🧪")
struct QdrantIndexerTests {

    /// Golden vector from Python: `uuid.uuid5(UUID('28e21975-d144-42eb-8eb8-fb0e5bfb0c80'), 'sha256:abc')`
    private static let goldenV5ForSha256Abc = UUID(uuidString: "3187e201-cfee-552c-a9e6-9571a859f23d")!

    private func makeMockSession() -> URLSession {
        let cosmicConfiguration = URLSessionConfiguration.ephemeral
        cosmicConfiguration.protocolClasses = [QdrantMockURLProtocol.self]
        return URLSession(configuration: cosmicConfiguration)
    }

    // 🌟 The Deterministic Key Test - Proving our UUIDv5 mapping magic
    @Test("Test deterministic UUIDv5 generation 🪄")
    func testDeterministicUUIDv5() {
        let hash1 = "sha256:abc"
        let hash2 = "sha256:abc"
        let hash3 = "sha256:xyz"

        let uuid1 = UUID.deterministicV5(from: hash1)
        let uuid2 = UUID.deterministicV5(from: hash2)
        let uuid3 = UUID.deterministicV5(from: hash3)

        #expect(uuid1 == uuid2, "Identical content hashes must produce identical UUIDv5 points! Symmetrical magic. 🌌")
        #expect(uuid1 != uuid3, "Different content hashes must produce different UUIDv5 points! No cloning. 🕵️‍♂️")

        // 🔮 Golden cross-check vs Python uuid.uuid5 (interop with bin/qdrant-upsert.py lane)
        #expect(
            uuid1 == Self.goldenV5ForSha256Abc,
            "UUIDv5 must match Python uuid.uuid5 for sha256:abc → \(Self.goldenV5ForSha256Abc)! 🤝"
        )

        let uuidString = uuid1.uuidString.lowercased()
        let versionChar = uuidString[uuidString.index(uuidString.startIndex, offsetBy: 14)]
        #expect(versionChar == "5", "UUIDv5 must carry version character '5' at index 14! 🔮")

        let variantChar = uuidString[uuidString.index(uuidString.startIndex, offsetBy: 19)]
        #expect(["8", "9", "a", "b"].contains(String(variantChar)), "UUIDv5 variant character at index 19 must be one of [8, 9, a, b]! 🎭")
    }

    // 🌟 The Vector Representation Test - Proving we can serialize both flat and named vectors
    @Test("Test vector JSON serialization formats 🧮")
    func testVectorSerialization() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let flatVector = QdrantVector.flat([0.1, -0.2, 0.9])
        let flatData = try encoder.encode(flatVector)
        let decodedFlat = try decoder.decode(QdrantVector.self, from: flatData)

        #expect(decodedFlat == flatVector, "Flat vector must encode and decode perfectly! 📏")
        let flatString = String(data: flatData, encoding: .utf8) ?? ""
        #expect(flatString == "[0.1,-0.2,0.9]", "Flat vector JSON must be a raw float array! 🎨")

        let namedVector = QdrantVector.named(["fast-all-minilm-l6-v2": [0.1, -0.2, 0.9]])
        let namedData = try encoder.encode(namedVector)
        let decodedNamed = try decoder.decode(QdrantVector.self, from: namedData)

        #expect(decodedNamed == namedVector, "Named vector must encode and decode perfectly! 🧭")
        let namedString = String(data: namedData, encoding: .utf8) ?? ""
        #expect(namedString.contains("fast-all-minilm-l6-v2"), "Named vector JSON must include the vector label! 🌌")
    }

    // 🌟 The Payload Thinness Test - Verifying exact fields, snake_case, and NO full body
    @Test("Test thin payload formatting — no full body 📜")
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
        let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let keys = Set(jsonObject?.keys.map { $0 } ?? [])

        #expect(keys == QdrantPayload.allowedKeys, "Payload must encode exactly the six §13 keys! 🐍")
        #expect(QdrantPayload.isThinPayloadJSON(jsonObject ?? [:]), "Payload must pass the thin-payload gate! 🪶")

        for forbidden in QdrantPayload.forbiddenKeys {
            #expect(!keys.contains(forbidden), "Payload must never include forbidden key '\(forbidden)'! 🚫")
        }

        let jsonString = String(data: data, encoding: .utf8) ?? ""
        #expect(jsonString.contains("\"content_hash\""), "Payload must use snake_case 'content_hash'! 🐍")
        #expect(jsonString.contains("\"source_path\""), "Payload must use snake_case 'source_path'! 📂")
        #expect(!jsonString.contains("\"narrative\""), "Payload must not smuggle narrative prose! 🙅")
        #expect(!jsonString.contains("\"body\""), "Payload must not smuggle body text! 🙅")
        #expect(!jsonString.contains("\"document\""), "Payload must not smuggle document text! 🙅")
    }

    // 🌟 Visibility gate — private/internal still index, but carry visibility for export filters
    @Test("Test visibility tags carried on thin payload 👓")
    func testVisibilityTagsCarried() throws {
        for cloak in ["public", "friends", "private", "internal"] {
            let payload = QdrantPayload(
                contentHash: "sha256:\(cloak)",
                visibility: cloak,
                project: "multibrain",
                date: "2026-07-15",
                tags: ["gotcha"],
                sourcePath: "07-Sessions/example.md"
            )
            let data = try JSONEncoder().encode(payload)
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            #expect(object?["visibility"] as? String == cloak, "Visibility \(cloak) must ride the payload! 🕶️")
            #expect(QdrantPayload.isThinPayloadJSON(object ?? [:]), "Cloaked payloads stay thin! 🪶")
        }
    }

    // 🌟 Point wire format — lowercase UUID id + thin payload + named vector
    @Test("Test makePoint builds §13 wire shape 🧭")
    func testMakePointWireShape() async throws {
        let indexer = QdrantIndexer(
            baseURL: URL(string: "http://127.0.0.1:16340")!,
            collectionName: "secondbrain_learnings",
            vectorName: "fast-all-minilm-l6-v2",
            session: makeMockSession()
        )

        let point = await indexer.makePoint(
            contentHash: "sha256:abc",
            vector: [0.1, 0.2, 0.3],
            visibility: "private",
            project: "multibrain",
            date: "2026-07-15",
            tags: ["insight/discovery"],
            sourcePath: "07-Sessions/2026-07-15--multibrain--codex.md"
        )

        #expect(point.id == Self.goldenV5ForSha256Abc, "makePoint must stamp golden UUIDv5! 🪄")
        #expect(point.payload.visibility == "private")

        let data = try JSONEncoder().encode(QdrantUpsertRequest(points: [point]))
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let points = root?["points"] as? [[String: Any]]
        let first = points?.first
        let idString = first?["id"] as? String
        let payload = first?["payload"] as? [String: Any]
        let vector = first?["vector"] as? [String: Any]

        #expect(idString == Self.goldenV5ForSha256Abc.uuidString.lowercased(), "Wire id must be lowercase UUID string! 🔡")
        #expect(QdrantPayload.isThinPayloadJSON(payload ?? [:]), "Upsert payload must be thin! 🪶")
        #expect(vector?["fast-all-minilm-l6-v2"] != nil, "Named vector must use MiniLM label! 🧮")

        let blob = String(data: data, encoding: .utf8) ?? ""
        for forbidden in QdrantPayload.forbiddenKeys {
            #expect(!blob.contains("\"\(forbidden)\""), "Upsert JSON must not contain '\(forbidden)'! 🚫")
        }
    }

    // 🌟 The Point Alchemy Success Test - Proving happy path + body inspection
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

        QdrantMockURLProtocol.register(port: port) { request in
            #expect(request.url?.path == "/collections/secondbrain_learnings/points", "Request must target points portal! 🌐")
            #expect(request.url?.query?.contains("wait=true") == true, "Request must specify wait=true query! ⏱️")
            #expect(request.httpMethod == "PUT", "Qdrant REST point upsert expects PUT method! 📥")

            let body = QdrantMockURLProtocol.requestBodyData(from: request)
            #expect(body != nil, "Upsert must carry a JSON body! 📦")
            if let body {
                let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
                let points = root?["points"] as? [[String: Any]]
                let first = points?.first
                #expect(first?["id"] as? String == Self.goldenV5ForSha256Abc.uuidString.lowercased())
                let payload = first?["payload"] as? [String: Any] ?? [:]
                #expect(QdrantPayload.isThinPayloadJSON(payload))
                let blob = String(data: body, encoding: .utf8) ?? ""
                #expect(!blob.contains("\"narrative\""))
                #expect(!blob.contains("\"body\""))
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, nil)
        }
        defer { QdrantMockURLProtocol.unregister(port: port) }

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
        #expect(success, "Vector indexing should succeed under serene skies! ☀️")
        #expect(!isDirty, "The indexer state must remain clean and pristine! 🧹")
    }

    // 🌟 Fail-open under network storm
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

        QdrantMockURLProtocol.register(port: port) { _ in
            throw URLError(.timedOut)
        }
        defer { QdrantMockURLProtocol.unregister(port: port) }

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
        #expect(!success, "Indexing should report failure when the server is unreachable! 🌩️")
        #expect(isDirty, "The index must be marked dirty to flag a future repair ritual! 🛠️")
    }

    // 🌟 Fail-open on HTTP 500 + flat vector
    @Test("Test point indexing on server error (Fail-Open) 🌧️")
    func testIndexPointServerError() async throws {
        let port = 16335
        let mockSession = makeMockSession()
        let indexer = QdrantIndexer(
            baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            collectionName: "secondbrain_learnings",
            vectorName: nil,
            session: mockSession
        )

        QdrantMockURLProtocol.register(port: port) { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, nil)
        }
        defer { QdrantMockURLProtocol.unregister(port: port) }

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
        #expect(!success, "Indexing must report failure when the server is throwing storms! ⛈️")
        #expect(isDirty, "The index must be marked dirty! 🛠️")
    }

    // 🌟 Dirty flag purification
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

        QdrantMockURLProtocol.register(port: port) { _ in
            throw URLError(.notConnectedToInternet)
        }
        defer { QdrantMockURLProtocol.unregister(port: port) }

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

        await indexer.resetDirty()
        let purifiedDirty = await indexer.isDirty
        #expect(!purifiedDirty, "The purification ritual must restore the index to a clean state! 💎")
    }

    // 🌟 Task 7 proof harness — §13 contract in one shot
    @Test("Task7 proof harness — UUIDv5 + thin + fail-open 🧾")
    func testTask7QdrantIndexerProofHarness() async throws {
        // 1) Deterministic id
        let id = UUID.deterministicV5(from: "sha256:abc")
        #expect(id == Self.goldenV5ForSha256Abc)

        // 2) Thin payload (no full body)
        let payload = QdrantPayload(
            contentHash: "sha256:abc",
            visibility: "internal",
            project: "multibrain",
            date: "2026-07-15",
            tags: ["gotcha"],
            sourcePath: "07-Sessions/proof.md"
        )
        let payloadData = try JSONEncoder().encode(payload)
        let payloadObject = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any] ?? [:]
        #expect(Set(payloadObject.keys) == QdrantPayload.allowedKeys)
        #expect(QdrantPayload.isThinPayloadJSON(payloadObject))

        // 3) Fail-open (no throw)
        let port = 16337
        let indexer = QdrantIndexer(
            baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            collectionName: "secondbrain_learnings",
            vectorName: "fast-all-minilm-l6-v2",
            session: makeMockSession()
        )
        QdrantMockURLProtocol.register(port: port) { _ in
            throw URLError(.cannotConnectToHost)
        }
        defer { QdrantMockURLProtocol.unregister(port: port) }

        let ok = await indexer.index(
            contentHash: "sha256:abc",
            vector: [0.01],
            visibility: "internal",
            project: "multibrain",
            date: "2026-07-15",
            tags: ["gotcha"],
            sourcePath: "07-Sessions/proof.md"
        )
        #expect(!ok)
        #expect(await indexer.isDirty)
    }
}
