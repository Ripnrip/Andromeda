// Proposed standalone test: Tests/AndromedaToolsTests/UpstreamHTTPBoundsTests.swift.
// Every execute uses injected callbacks/manual deadlines; no URLProtocol globals or network exist here.
@testable import AndromedaTools
import Foundation
import Testing

@Suite("AndromedaTools.UpstreamHTTP transport bounds", .timeLimit(.minutes(1)))
struct UpstreamHTTPBoundsTests {
    private static let canary = "TRANSPORT-CANARY-CREDENTIAL-NOT-FOR-ERRORS"

    /// Pins old initializer syntax/public seams without executing the production network boundary.
    @Test("legacy initializer and value/protocol seams remain available")
    func sourceCompatibility() {
        let original = URLSessionUpstreamHTTP(maxDownloadBytes: 4)
        let defaults = URLSessionUpstreamHTTP()
        let constructor: (Int) -> URLSessionUpstreamHTTP = URLSessionUpstreamHTTP.init(maxDownloadBytes:)
        let seam: any UpstreamHTTPExecuting = original
        #expect(original.maxDownloadBytes == 4)
        #expect(constructor(4).maxDownloadBytes == 4)
        #expect(defaults.maxDownloadBytes == 8 * 1_024 * 1_024)
        #expect(defaults.policy == UpstreamHTTPPolicy())
        _ = seam
    }

    /// Tests all invalid budget axes before a task or timer can be created; nonthrowing init is deliberate.
    @Test("invalid budgets fail before session creation")
    func invalidBudgets() async throws {
        let request = try fixtureRequest()
        let cases: [(Int, UpstreamHTTPPolicy, UpstreamHTTPTransportError)] = [
            (0, .init(), .invalidConfiguration(.downloadBytes)),
            (-1, .init(), .invalidConfiguration(.downloadBytes)),
            (Int.max, .init(), .invalidConfiguration(.downloadBytes)),
            (4, .init(maxRequestBytes: 0), .invalidConfiguration(.requestBytes)),
            (4, .init(maxRequestBytes: Int.max), .invalidConfiguration(.requestBytes)),
            (4, .init(maxHeaderFields: 0), .invalidConfiguration(.headerFields)),
            (4, .init(maxHeaderFields: 129), .invalidConfiguration(.headerFields)),
            (4, .init(maxConcurrentRequests: 0), .invalidConfiguration(.concurrency)),
            (4, .init(maxConcurrentRequests: 33), .invalidConfiguration(.concurrency)),
            (4, .init(requestTimeoutSeconds: 0), .invalidConfiguration(.requestDeadline)),
            (4, .init(requestTimeoutSeconds: -.infinity), .invalidConfiguration(.requestDeadline)),
            (4, .init(requestTimeoutSeconds: .nan), .invalidConfiguration(.requestDeadline)),
            (4, .init(resourceTimeoutSeconds: 0), .invalidConfiguration(.resourceDeadline)),
            (4, .init(resourceTimeoutSeconds: .infinity), .invalidConfiguration(.resourceDeadline)),
            (4, .init(resourceTimeoutSeconds: .nan), .invalidConfiguration(.resourceDeadline)),
            (4, .init(requestTimeoutSeconds: 10, resourceTimeoutSeconds: 9), .invalidConfiguration(.resourceDeadline)),
            (4, .init(resourceTimeoutSeconds: 301), .invalidConfiguration(.resourceDeadline)),
        ]
        for (download, policy, error) in cases {
            let driver = CallbackDriver { _, _ in Issue.record("invalid policy reached task boundary") }
            let deadlines = ManualDeadlines()
            let http = executor(driver, deadlines: deadlines, limit: download, policy: policy)
            await expectFailure(error) { try await http.execute(request) }
            #expect(driver.handles.isEmpty)
            #expect(deadlines.tokens.isEmpty)
        }
    }

    /// Accounts for UTF-8 URL, method, headers, framing and body together; no body-only loophole.
    @Test("aggregate request bytes are exact and oversize requests never reach a driver")
    func requestBytes() async throws {
        let request = try fixtureRequest(headers: ["X-Fixture": "é"], body: Data([0, 255, 1]))
        let headerBytes = request.headers.reduce(0) { $0 + $1.key.utf8.count + $1.value.utf8.count + 4 }
        let total = request.method.utf8.count + request.url.absoluteString.utf8.count
            + headerBytes + (request.body?.count ?? 0) + 4
        let driver = CallbackDriver { native, events in
            #expect(native.httpBody == request.body)
            #expect(native.value(forHTTPHeaderField: "X-Fixture") == "é")
            #expect(native.httpShouldHandleCookies == false)
            #expect(native.cachePolicy == .reloadIgnoringLocalCacheData)
            #expect(native.timeoutInterval == 30)
            sendHead(events, url: request.url, length: 0)
            events.completed(nil)
        }
        let exact = executor(driver, policy: .init(maxRequestBytes: total))
        #expect(try await exact.execute(request) == UpstreamHTTPResponse(status: 200, body: Data()))
        let rejecting = CallbackDriver { _, _ in Issue.record("oversized request reached task boundary") }
        let deadlines = ManualDeadlines()
        let tooSmall = executor(rejecting, deadlines: deadlines, policy: .init(maxRequestBytes: total - 1))
        await expectFailure(.requestTooLarge(limit: total - 1)) { try await tooSmall.execute(request) }
        #expect(rejecting.handles.isEmpty)
        #expect(deadlines.tokens.isEmpty)
        let largeBody = try fixtureRequest(body: Data(repeating: 42, count: 1_025))
        let bodyBounded = executor(rejecting, policy: .init(maxRequestBytes: 1_024))
        await expectFailure(.requestTooLarge(limit: 1_024)) { try await bodyBounded.execute(largeBody) }
    }

    /// Rejects identity/framing overrides, duplicate case-insensitive fields and CRLF/control injection.
    /// These are transport syntax rules, not a claim that arbitrary GitHub/Slack operations are safe.
    @Test("unsafe request metadata fails before task creation")
    func requestMetadata() async throws {
        let request = try fixtureRequest()
        let cases: [(UpstreamHTTPRequest, UpstreamHTTPPolicy, UpstreamHTTPTransportError)] = [
            (try fixtureRequest(url: "http://fixture.invalid/path"), .init(), .invalidRequest(.url)),
            (try fixtureRequest(url: "https://user:password@fixture.invalid/path"), .init(), .invalidRequest(.url)),
            (try fixtureRequest(url: "https://fixture.invalid/path#fragment"), .init(), .invalidRequest(.url)),
            (try fixtureRequest(method: "GET\r\nX: bad"), .init(), .invalidRequest(.method)),
            (try fixtureRequest(method: "CONNECT"), .init(), .invalidRequest(.method)),
            (try fixtureRequest(method: "TRACE"), .init(), .invalidRequest(.method)),
            (try fixtureRequest(headers: ["Host": "elsewhere.invalid"]), .init(), .invalidRequest(.forbiddenHeader)),
            (try fixtureRequest(headers: ["Content-Length": "1"]), .init(), .invalidRequest(.forbiddenHeader)),
            (try fixtureRequest(headers: ["Transfer-Encoding": "chunked"]), .init(), .invalidRequest(.forbiddenHeader)),
            (try fixtureRequest(headers: ["Proxy-Authorization": Self.canary]), .init(), .invalidRequest(.forbiddenHeader)),
            (try fixtureRequest(headers: ["X-Value": "ok\r\nAuthorization: bad"]), .init(), .invalidRequest(.headerSyntax)),
            (try fixtureRequest(headers: ["X Bad": "value"]), .init(), .invalidRequest(.headerSyntax)),
            (try fixtureRequest(headers: ["X-Value": "a\0b"]), .init(), .invalidRequest(.headerSyntax)),
            (try fixtureRequest(headers: ["Authorization": "one", "authorization": "two"]), .init(), .invalidRequest(.duplicateHeader)),
            (try fixtureRequest(headers: ["X-One": "1", "X-Two": "2"]), .init(maxHeaderFields: 1), .invalidRequest(.tooManyHeaders)),
        ]
        for (candidate, policy, expected) in cases {
            let driver = CallbackDriver { _, _ in Issue.record("invalid metadata reached task boundary") }
            await expectFailure(expected) { try await executor(driver, policy: policy).execute(candidate) }
            #expect(driver.handles.isEmpty)
        }
        // An explicit origin credential is preserved on an otherwise valid HTTPS request.
        let valid = UpstreamHTTPRequest(method: request.method, url: request.url, headers: ["Authorization": Self.canary])
        _ = try UpstreamHTTPValidation.validate(valid, policy: .init())
    }

    /// Origin identity folds DNS case and default HTTPS port but never equates a different host/port/scheme.
    @Test("origin identity is narrow and canonical")
    func origins() throws {
        let implicit = UpstreamHTTPOrigin(url: try fixtureURL("https://FIXTURE.invalid/a"))
        let explicit = UpstreamHTTPOrigin(url: try fixtureURL("https://fixture.invalid:443/b"))
        #expect(implicit != nil)
        #expect(implicit == explicit)
        #expect(implicit != UpstreamHTTPOrigin(url: try fixtureURL("https://fixture.invalid:444/a")))
        #expect(implicit != UpstreamHTTPOrigin(url: try fixtureURL("https://other.invalid/a")))
        #expect(UpstreamHTTPOrigin(url: try fixtureURL("http://fixture.invalid/a")) == nil)
    }

    /// Exercises arbitrary binary chunk boundaries, including empty chunks and exactly-limit success.
    @Test("complete binary body at the limit is not truncated")
    func exactBody() async throws {
        let request = try fixtureRequest()
        let bytes = Data([0, 255, 128, 7])
        let driver = CallbackDriver { _, events in
            sendHead(events, url: request.url, length: 4)
            events.data(Data())
            events.data(Data(bytes.prefix(1)))
            events.data(Data(bytes.dropFirst()))
            events.completed(nil)
        }
        let response = try await executor(driver, limit: bytes.count).execute(request)
        #expect(response == UpstreamHTTPResponse(status: 200, body: bytes))
        #expect(driver.handles.first?.snapshot.cancelRequested == false)
        #expect(driver.handles.first?.snapshot.invalidationCalls == 1)
    }

    /// Unknown/untrusted lengths do not disable actual-chunk limits; one oversized chunk is wholly rejected.
    /// The pure collector oracle proves no prefix of the offending chunk was appended before the throw.
    @Test("oversize unknown-length streams throw instead of returning partial success")
    func chunkOverflow() async throws {
        let request = try fixtureRequest()
        let origin = try #require(UpstreamHTTPOrigin(url: request.url))
        var collector = UpstreamHTTPCollector(origin: origin, limit: 4)
        try collector.receive(head(url: request.url))
        try collector.receive(Data("ab".utf8))
        expectSynchronousFailure(.responseTooLarge(limit: 4)) { try collector.receive(Data("cde".utf8)) }
        #expect(collector.body == Data("ab".utf8))
        let driver = CallbackDriver { _, events in
            sendHead(events, url: request.url)
            events.data(Data("ab".utf8))
            events.data(Data("cde".utf8))
            events.completed(nil) // malicious/late success cannot replace the first overflow
        }
        await expectFailure(.responseTooLarge(limit: 4)) { try await executor(driver, limit: 4).execute(request) }
        #expect(driver.handles.first?.snapshot.cancelRequested == true)
        let single = CallbackDriver { _, events in
            sendHead(events, url: request.url)
            events.data(Data(repeating: 0, count: 64 * 1_024))
            events.completed(nil)
        }
        await expectFailure(.responseTooLarge(limit: 8)) { try await executor(single, limit: 8).execute(request) }
    }

    /// Advertised oversize fails at headers, before any Data callback; HEAD/304 lengths describe a representation.
    @Test("advertised oversize is rejected but bodyless representation lengths are not downloaded bytes")
    func advertisedLengths() async throws {
        let request = try fixtureRequest()
        let oversized = CallbackDriver { _, events in
            #expect(!events.response(head(url: request.url, length: Int64.max)))
            events.completed(nil)
        }
        await expectFailure(.responseTooLarge(limit: 4)) { try await executor(oversized, limit: 4).execute(request) }
        for status in [200, 204, 304] {
            let driver = CallbackDriver { _, events in
                sendHead(events, url: request.url, status: status, length: Int64.max, expectsBody: false)
                events.completed(nil)
            }
            let result = try await executor(driver, limit: 4).execute(request)
            #expect(result.status == status)
            #expect(result.body.isEmpty)
        }
    }

    /// Foundation errors after a prefix fail the call. HTTP failure status is still a complete response,
    /// leaving broker-specific body redaction/status interpretation at the preserved protocol boundary.
    @Test("midstream failures are explicit and non-2xx complete responses remain compatible")
    func midstreamFailure() async throws {
        let request = try fixtureRequest()
        let failure = UpstreamHTTPTransportError.sanitizing(NSError(
            domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost,
            userInfo: [NSLocalizedDescriptionKey: Self.canary]
        ))
        let broken = CallbackDriver { _, events in
            sendHead(events, url: request.url)
            events.data(Data(Self.canary.utf8))
            events.completed(failure)
            events.completed(nil)
        }
        await expectFailure(failure) { try await executor(broken).execute(request) }
        let complete = CallbackDriver { _, events in
            sendHead(events, url: request.url, status: 401, length: 2)
            events.data(Data("{}".utf8))
            events.completed(nil)
        }
        #expect(try await executor(complete).execute(request) == UpstreamHTTPResponse(status: 401, body: Data("{}".utf8)))
    }

    /// Missing/non-HTTP heads, altered origins, duplicate final heads and invalid framing never yield status -1.
    @Test("response metadata and framing fail closed")
    func invalidResponses() async throws {
        let request = try fixtureRequest()
        let wrong = try fixtureURL("https://other.invalid/path")
        let scripts: [(@Sendable (URLRequest, UpstreamHTTPTransferEvents) -> Void, UpstreamHTTPTransportError)] = [
            ({ _, events in events.completed(nil) }, .invalidResponse),
            ({ _, events in events.data(Data([1])); events.completed(nil) }, .invalidResponse),
            ({ _, events in
                _ = events.response(UpstreamHTTPResponseHead(status: nil, origin: nil, expectedLength: -1, lengthIsExact: false, expectsBody: true))
            }, .invalidResponse),
            ({ _, events in _ = events.response(head(url: wrong)) }, .responseOriginMismatch),
            ({ _, events in
                sendHead(events, url: request.url)
                _ = events.response(head(url: request.url))
            }, .invalidResponse),
            ({ _, events in
                sendHead(events, url: request.url, length: 4)
                events.data(Data("abc".utf8)); events.completed(nil)
            }, .responseLengthMismatch),
            ({ _, events in
                sendHead(events, url: request.url, expectsBody: false)
                events.data(Data([1]))
            }, .invalidResponse),
        ]
        for (script, error) in scripts {
            let driver = CallbackDriver(script: script)
            await expectFailure(error) { try await executor(driver).execute(request) }
        }
        // A decoded (e.g. gzip) body can legitimately differ from encoded Content-Length.
        let decoded = CallbackDriver { _, events in
            sendHead(events, url: request.url, length: 2, exact: false)
            events.data(Data("abcd".utf8)); events.completed(nil)
        }
        #expect(try await executor(decoded, limit: 4).execute(request).body == Data("abcd".utf8))
    }

    /// The core cancels on redirect/challenge rejection and never turns their follow-on completion into success.
    /// Native redirect completionHandler(nil) / trust handling still require the separate Darwin adapter gate.
    @Test("redirect and non-trust challenge rejection cancels the real task boundary")
    func redirectAndAuthentication() async throws {
        let request = try fixtureRequest(headers: ["Authorization": Self.canary], body: Data(Self.canary.utf8))
        let errors: [UpstreamHTTPTransportError] = [.redirectDenied, .authenticationDenied]
        for error in errors {
            let driver = CallbackDriver { native, events in
                #expect(native.value(forHTTPHeaderField: "Authorization") == Self.canary)
                events.rejected(error)
                events.completed(nil)
            }
            await expectFailure(error) { try await executor(driver).execute(request) }
            #expect(driver.handles.count == 1)
            #expect(driver.handles.first?.snapshot.cancelRequested == true)
        }
    }

    /// Fires the absolute header deadline without sleeping; no native success is possible after expiry.
    @Test("response-header deadline cancels an operation with no headers")
    func headerDeadline() async throws {
        let request = try fixtureRequest()
        let driver = CallbackDriver { _, _ in }
        let deadlines = ManualDeadlines()
        let http = executor(driver, deadlines: deadlines)
        let task = Task { try await http.execute(request) }
        defer { task.cancel() }
        var starts = driver.started.makeAsyncIterator()
        let handle = try #require(await starts.next())
        defer { handle.acknowledgeInvalidation() }
        #expect(deadlines.tokens.map(\.seconds) == [30, 60])
        deadlines.tokens[0].fire()
        await expectFailure(.deadlineExceeded(.responseHeaders)) { try await task.value }
        #expect(handle.snapshot.cancelRequested)
        #expect(deadlines.tokens.allSatisfy { $0.isCancelled })
    }

    /// Header acceptance wins over a stale in-flight header timer, but resource deadline never renews per chunk.
    @Test("stale header timers are ignored while resource deadline survives streaming progress")
    func resourceDeadline() async throws {
        let request = try fixtureRequest()
        let driver = CallbackDriver { _, events in sendHead(events, url: request.url) }
        let deadlines = ManualDeadlines()
        let http = executor(driver, deadlines: deadlines)
        let task = Task { try await http.execute(request) }
        defer { task.cancel() }
        var starts = driver.started.makeAsyncIterator()
        let handle = try #require(await starts.next())
        defer { handle.acknowledgeInvalidation() }
        #expect(deadlines.tokens[0].isCancelled)
        deadlines.tokens[0].fire(evenIfCancelled: true) // model a timer callback already dispatched
        #expect(handle.snapshot.invalidationCalls == 0)
        handle.events.data(Data("a".utf8))
        #expect(!deadlines.tokens[1].isCancelled)
        deadlines.tokens[1].fire()
        await expectFailure(.deadlineExceeded(.resource)) { try await task.value }
        #expect(handle.snapshot.cancelRequested)
    }

    /// A deadline during installation is remembered; even an unresumed driver task must be invalidated.
    @Test("deadline during timer/task installation cannot start the suspended task")
    func installationDeadline() async throws {
        let request = try fixtureRequest()
        let driver = CallbackDriver { _, _ in Issue.record("expired operation was resumed") }
        let deadlines = ManualDeadlines(fireImmediatelyAtIndex: 0)
        await expectFailure(.deadlineExceeded(.responseHeaders)) {
            try await executor(driver, deadlines: deadlines).execute(request)
        }
        let handle = try #require(driver.handles.first)
        #expect(handle.snapshot.resumeCalls == 0)
        #expect(handle.snapshot.cancelRequested)
        #expect(deadlines.tokens.allSatisfy { $0.isCancelled })
    }

    /// Copies share fail-fast admission. Cancellation does NOT release a permit before teardown acknowledgement.
    /// Uses an AsyncStream only for a bounded test latch, never to buffer response Data.
    @Test("concurrency and cancellation remain bounded through native teardown")
    func cancellationAndAdmission() async throws {
        let request = try fixtureRequest()
        let driver = CallbackDriver(automaticallyInvalidates: false) { _, events in
            sendHead(events, url: request.url)
            events.data(Data("a".utf8))
        }
        let http = executor(driver, policy: .init(maxConcurrentRequests: 1))
        let copy = http
        let task = Task { try await http.execute(request) }
        defer { task.cancel() }
        var starts = driver.started.makeAsyncIterator()
        let handle = try #require(await starts.next())
        defer { handle.acknowledgeInvalidation() }
        await expectFailure(.busy) { try await copy.execute(request) }
        #expect(driver.handles.count == 1)
        task.cancel()
        #expect(handle.snapshot.cancelRequested)
        await expectFailure(.busy) { try await http.execute(request) }
        #expect(driver.handles.count == 1)
        handle.acknowledgeInvalidation()
        await expectCancellation { try await task.value }
        // Once acknowledged, another operation is admitted; finish it deterministically too.
        let next = Task { try await copy.execute(request) }
        defer { next.cancel() }
        let second = try #require(await starts.next())
        defer { second.acknowledgeInvalidation() }
        second.events.completed(nil)
        second.acknowledgeInvalidation()
        #expect(try await next.value.body == Data("a".utf8))
    }

    /// A selected failure or deadline retains admission until native teardown; no early-release timeout facade.
    @Test("midstream failure and deadline hold admission until acknowledgement", arguments: [false, true])
    func failureAcknowledgement(deadline: Bool) async throws {
        let request = try fixtureRequest()
        let failure = UpstreamHTTPTransportError.networkFailure(code: NSURLErrorNetworkConnectionLost)
        let driver = CallbackDriver(automaticallyInvalidates: false) { _, events in
            sendHead(events, url: request.url)
            events.data(Data("a".utf8))
            if !deadline { events.completed(failure) }
        }
        let deadlines = ManualDeadlines()
        let http = executor(driver, deadlines: deadlines, policy: .init(maxConcurrentRequests: 1))
        let task = Task { try await http.execute(request) }
        defer { task.cancel() }
        var starts = driver.started.makeAsyncIterator()
        let handle = try #require(await starts.next())
        defer { handle.acknowledgeInvalidation() }
        if deadline { deadlines.tokens[1].fire() }
        #expect(handle.snapshot.cancelRequested)
        #expect(handle.snapshot.invalidationCalls == 1)
        await expectFailure(.busy) { try await http.execute(request) }
        #expect(driver.handles.count == 1)
        handle.acknowledgeInvalidation()
        let expected: UpstreamHTTPTransportError = deadline ? .deadlineExceeded(.resource) : failure
        await expectFailure(expected) { try await task.value }
    }

    /// Selected success retains admission until invalidation too; duplicate post-terminal events are inert.
    @Test("completed outcomes wait for invalidation and ignore duplicate late callbacks")
    func completionAcknowledgement() async throws {
        let request = try fixtureRequest()
        let driver = CallbackDriver(automaticallyInvalidates: false) { _, events in
            sendHead(events, url: request.url, length: 1)
            events.data(Data([7])); events.completed(nil)
        }
        let http = executor(driver, policy: .init(maxConcurrentRequests: 1))
        let task = Task { try await http.execute(request) }
        defer { task.cancel() }
        var starts = driver.started.makeAsyncIterator()
        let handle = try #require(await starts.next())
        defer { handle.acknowledgeInvalidation() }
        #expect(handle.snapshot.invalidationCalls == 1)
        #expect(!handle.snapshot.cancelRequested)
        await expectFailure(.busy) { try await http.execute(request) }
        handle.acknowledgeInvalidation()
        #expect(try await task.value.body == Data([7]))
        // Misbehaving late callbacks cannot append bytes, invalidate again, or resume the continuation twice.
        handle.events.data(Data(repeating: 0, count: 64 * 1_024))
        handle.events.completed(.networkFailure(code: 1))
        handle.events.rejected(.redirectDenied)
        handle.events.invalidated(nil)
        #expect(!handle.events.response(head(url: request.url)))
        #expect(handle.snapshot.invalidationCalls == 1)
    }

    /// A completed response does not hide task cancellation while execute is awaiting native invalidation.
    @Test("cancellation after completion still propagates CancellationError")
    func cancelAfterCompletion() async throws {
        let request = try fixtureRequest()
        let driver = CallbackDriver(automaticallyInvalidates: false) { _, events in
            sendHead(events, url: request.url, length: 0); events.completed(nil)
        }
        let task = Task { try await executor(driver).execute(request) }
        defer { task.cancel() }
        var starts = driver.started.makeAsyncIterator()
        let handle = try #require(await starts.next())
        defer { handle.acknowledgeInvalidation() }
        task.cancel()
        handle.acknowledgeInvalidation()
        await expectCancellation { try await task.value }
    }

    /// Explicit self-cancellation is confined to the test's current Task; no shared cancellation registry exists.
    @Test("cancellation before start and during suspended task creation never resumes a task")
    func prestartCancellation() async throws {
        let request = try fixtureRequest()
        let before = CallbackDriver { _, _ in Issue.record("pre-cancelled operation reached resume") }
        let deadlines = ManualDeadlines()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await executor(before, deadlines: deadlines).execute(request)
        }
        defer { task.cancel() }
        await expectCancellation { try await task.value }
        #expect(before.handles.isEmpty)
        #expect(deadlines.tokens.isEmpty)
        let during = CallbackDriver(cancelCurrentTaskDuringCreation: true) { _, _ in
            Issue.record("cancelled suspended task reached resume")
        }
        let installing = Task { try await executor(during).execute(request) }
        defer { installing.cancel() }
        await expectCancellation { try await installing.value }
        let handle = try #require(during.handles.first)
        #expect(handle.snapshot.resumeCalls == 0)
        #expect(handle.snapshot.cancelRequested)
    }

    /// Bypasses execute's entry checks: an already-cancelled child calls the internal transfer directly.
    /// onCancel must select .cancelled while phase is .new; continuation registration consumes it exactly
    /// once and returns a typed Result normally, without any driver handle or deadline ownership.
    @Test("internal run consumes cancellation before continuation registration")
    func cancellationBeforeContinuation() async throws {
        let request = try fixtureRequest()
        let origin = try #require(UpstreamHTTPOrigin(url: request.url))
        let transfer = UpstreamHTTPTransfer(origin: origin, limit: 4)
        let native = URLRequest(url: request.url)
        let driver = CallbackDriver { _, _ in Issue.record("pre-continuation cancellation reached resume") }
        let deadlines = ManualDeadlines()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await transfer.run(request: native, policy: .init(), driver: driver, deadlines: deadlines)
        }
        defer { task.cancel() }
        #expect(await task.value == .failure(.cancelled))
        #expect(driver.handles.isEmpty)
        #expect(deadlines.tokens.isEmpty)
    }

    /// Deliberately acknowledges invalidation inside the factory before it returns its suspended handle.
    /// This is a defensive publication oracle, NOT proof that Darwin can emit that native ordering.
    /// The already-terminal returned handle must receive orphan teardown outside the core lock, never resume.
    @Test("factory-time invalidation cannot republish or resume a terminal handle")
    func factoryInvalidation() async throws {
        let request = try fixtureRequest()
        let driver = CallbackDriver(factoryScript: { _, handle in
            handle.acknowledgeInvalidation()
        }) { _, _ in Issue.record("terminal factory handle started a script") }
        let deadlines = ManualDeadlines()
        await expectFailure(.sessionInvalidated) {
            try await executor(driver, deadlines: deadlines).execute(request)
        }
        let handle = try #require(driver.handles.first)
        #expect(driver.handles.count == 1)
        #expect(handle.snapshot.resumeInvocations == 0)
        #expect(handle.snapshot.resumeCalls == 0)
        #expect(handle.snapshot.invalidationCalls == 1)
        #expect(handle.snapshot.cancelRequested)
        #expect(handle.snapshot.acknowledged)
        #expect(deadlines.tokens.allSatisfy { $0.isCancelled })
        // Forced stale callbacks cannot reopen collection or schedule a second teardown/result.
        for timer in deadlines.tokens { timer.fire(evenIfCancelled: true) }
        handle.events.completed(nil)
        handle.events.invalidated(nil)
        #expect(!handle.events.response(head(url: request.url)))
        #expect(handle.snapshot.invalidationCalls == 1)
    }

    /// Emits an intentionally out-of-contract complete head/body/completion before factory return.
    /// Without early acknowledgement registration must cancel the unresumed handle and await teardown;
    /// with early acknowledgement it must instead dispose of the orphan without reviving terminal custody.
    /// Both retain the complete result, never a prefix/error body. Native reachability remains UNPROVED.
    @Test("finish before handle registration preserves complete result and terminal publication", arguments: [false, true])
    func factoryCompletion(acknowledgeBeforeReturn: Bool) async throws {
        let request = try fixtureRequest()
        let bytes = Data([0, 255, 7, 128])
        let driver = CallbackDriver(automaticallyInvalidates: false, factoryScript: { native, handle in
            sendHead(handle.events, url: request.url, length: Int64(bytes.count))
            #expect(native.url == request.url)
            handle.events.data(bytes)
            handle.events.completed(nil)
            if acknowledgeBeforeReturn { handle.acknowledgeInvalidation() }
        }) { _, _ in Issue.record("factory-completed handle reached resume") }
        let deadlines = ManualDeadlines()
        let http = executor(driver, deadlines: deadlines, limit: bytes.count, policy: .init(maxConcurrentRequests: 1))
        let task = Task { try await http.execute(request) }
        // On an assertion/latch failure, never leave the child waiting for this fixture's manual teardown.
        defer { task.cancel(); driver.requestCleanup() }
        var teardowns = driver.teardownRequested.makeAsyncIterator()
        try #require(await teardowns.next())
        let handle = try #require(driver.handles.first)
        defer { handle.acknowledgeInvalidation() }
        #expect(handle.snapshot.resumeInvocations == 0)
        #expect(handle.snapshot.resumeCalls == 0)
        #expect(handle.snapshot.invalidationCalls == 1)
        #expect(handle.snapshot.cancelRequested)
        #expect(handle.snapshot.acknowledged == acknowledgeBeforeReturn)
        #expect(deadlines.tokens.allSatisfy { $0.isCancelled })
        if !acknowledgeBeforeReturn {
            await expectFailure(.busy) { try await http.execute(request) }
            #expect(driver.handles.count == 1)
        }
        handle.acknowledgeInvalidation()
        #expect(try await task.value == UpstreamHTTPResponse(status: 200, body: bytes))
        let invalid = try fixtureRequest(method: "TRACE")
        await expectFailure(.invalidRequest(.method)) { try await http.execute(invalid) }
        handle.events.completed(.networkFailure(code: 1))
        handle.events.invalidated(nil)
        #expect(!handle.events.response(head(url: request.url)))
        #expect(handle.snapshot.invalidationCalls == 1)
    }

    /// Registration has committed start when this handle's resume witness is entered. Its instance-owned
    /// synchronous hook self-cancels immediately before or after applying the fixture's native resume effect.
    /// Re-entrant cancellation applies invalidation outside the core lock, deterministically forcing both
    /// orders without parking a cooperative thread, sleeping, a semaphore, or a global handler.
    /// The one-element settled latch publishes only after both ordered effects; teardown acknowledgement
    /// remains manual so even the zero-start case proves admission is held until actual fixture teardown.
    @Test("post-registration native resume and cancellation effects obey both orders", arguments: [
        ResumeEffectOrder.cancellationBeforeResume, .resumeBeforeCancellation,
    ])
    func resumeCancellationEffects(order: ResumeEffectOrder) async throws {
        let request = try fixtureRequest()
        let driver = ResumeEffectDriver(order: order) { _, events in
            sendHead(events, url: request.url)
            events.data(Data([7])) // a started operation may have sent/received material before cancellation
        }
        let deadlines = ManualDeadlines()
        let http = executor(driver, deadlines: deadlines, policy: .init(maxConcurrentRequests: 1))
        let task = Task { try await http.execute(request) }
        // Failure cleanup also supplies the manual acknowledgement after requesting cancellation.
        defer { task.cancel(); driver.requestCleanup() }
        var settled = driver.settled.makeAsyncIterator()
        try #require(await settled.next())
        let handle = try #require(driver.handle)
        defer { handle.acknowledgeInvalidation() }
        let beforeTeardown = handle.snapshot
        #expect(beforeTeardown.resumeInvocations == 1) // start committed, not a pre-publication rejection
        #expect(beforeTeardown.invalidationCalls == 1)
        #expect(beforeTeardown.cancelRequested)
        #expect(!beforeTeardown.acknowledged)
        switch order {
        case .cancellationBeforeResume:
            #expect(beforeTeardown.effects == [.cancellationApplied, .resumeSuppressed])
            #expect(beforeTeardown.scriptStarts == 0)
        case .resumeBeforeCancellation:
            #expect(beforeTeardown.effects == [.resumeApplied, .cancellationApplied])
            #expect(beforeTeardown.scriptStarts == 1)
        }
        #expect(deadlines.tokens.allSatisfy { $0.isCancelled })
        await expectFailure(.busy) { try await http.execute(request) }
        handle.acknowledgeInvalidation()
        await expectCancellation { try await task.value }
        #expect(handle.snapshot.acknowledged)
        // Admission is now released: a pre-native validation probe reaches its own error, not busy.
        let invalid = try fixtureRequest(method: "TRACE")
        await expectFailure(.invalidRequest(.method)) { try await http.execute(invalid) }
    }

    /// Forces cleanup and owning-child cancellation during factory setup before publication.
    /// A one-shot optional handle snapshot would miss this window. Sticky cleanup must acknowledge
    /// the later handle, let the child settle as cancellation, and leave no resume/script activity.
    @Test("manual fixture cleanup remembers handles published after cancellation")
    func cleanupBeforeHandlePublication() async throws {
        let request = try fixtureRequest()
        let callback = CallbackDriver(
            automaticallyInvalidates: false, cancelAndCleanupBeforePublication: true
        ) { _, _ in Issue.record("cleanup-owned callback handle must not start") }
        let callbackHTTP = executor(callback, deadlines: ManualDeadlines())
        defer { callback.requestCleanup() }
        let callbackTask = Task { try await callbackHTTP.execute(request) }
        defer { callbackTask.cancel(); callback.requestCleanup() }
        await expectCancellation { try await callbackTask.value }
        let callbackHandle = try #require(callback.handles.first)
        #expect(callbackHandle.snapshot.acknowledged)
        #expect(callbackHandle.snapshot.resumeInvocations == 0)

        let effect = ResumeEffectDriver(
            order: .resumeBeforeCancellation, cancelAndCleanupBeforePublication: true
        ) { _, _ in Issue.record("cleanup-owned effect handle must not start") }
        let effectHTTP = executor(effect, deadlines: ManualDeadlines())
        defer { effect.requestCleanup() }
        let effectTask = Task { try await effectHTTP.execute(request) }
        defer { effectTask.cancel(); effect.requestCleanup() }
        await expectCancellation { try await effectTask.value }
        let effectHandle = try #require(effect.handle)
        #expect(effectHandle.snapshot.acknowledged)
        #expect(effectHandle.snapshot.resumeInvocations == 0)
        #expect(effectHandle.snapshot.scriptStarts == 0)
    }

    /// Native invalidation without completion, or an invalidation error after success, fails closed.
    @Test("unexpected invalidation cannot fabricate success")
    func unexpectedInvalidation() async throws {
        let request = try fixtureRequest()
        let abrupt = CallbackDriver { _, events in events.invalidated(nil) }
        await expectFailure(.sessionInvalidated) { try await executor(abrupt).execute(request) }
        let broken = CallbackDriver(automaticallyInvalidates: false) { _, events in
            sendHead(events, url: request.url, length: 0); events.completed(nil)
        }
        let task = Task { try await executor(broken).execute(request) }
        defer { task.cancel() }
        var starts = broken.started.makeAsyncIterator()
        let handle = try #require(await starts.next())
        defer { handle.acknowledgeInvalidation() }
        handle.acknowledgeInvalidation(error: .networkFailure(code: 42))
        await expectFailure(.networkFailure(code: 42)) { try await task.value }
    }

    /// Errors retain classifications/numbers only: credential-bearing descriptions, URLs and body fragments disappear.
    @Test("transport error descriptions and reflection never retain credential material")
    func errorPrivacy() {
        let native = NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost, userInfo: [
            NSLocalizedDescriptionKey: Self.canary,
            NSURLErrorFailingURLStringErrorKey: "https://fixture.invalid/\(Self.canary)",
            "body": Self.canary,
        ])
        let unknown = NSError(domain: Self.canary, code: 42, userInfo: [NSLocalizedDescriptionKey: Self.canary])
        let errors: [UpstreamHTTPTransportError] = [
            .sanitizing(native), .sanitizing(unknown), .requestTooLarge(limit: 4),
            .responseTooLarge(limit: 4), .redirectDenied, .authenticationDenied,
            .invalidRequest(.headerSyntax), .deadlineExceeded(.resource), .cancelled,
        ]
        for error in errors {
            #expect(!error.localizedDescription.contains(Self.canary))
            #expect(!String(reflecting: error).contains(Self.canary))
        }
        #expect(UpstreamHTTPTransportError.sanitizing(unknown) == .networkFailure(code: nil))
        #expect(UpstreamHTTPTransportError.sanitizing(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)) == .deadlineExceeded(.foundation))
        #expect(UpstreamHTTPTransportError.sanitizing(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)) == .cancelled)
    }

    /// A realistic binary bulk payload is delivered by chunk callbacks; no byte-wise suspension/timing oracle.
    @Test("bulk callback transfer preserves complete bytes")
    func bulkChunks() async throws {
        let request = try fixtureRequest()
        let payload = Data(repeating: 173, count: 1_400_000)
        let driver = CallbackDriver { _, events in
            sendHead(events, url: request.url, length: Int64(payload.count))
            for offset in stride(from: 0, to: payload.count, by: 64 * 1_024) {
                events.data(payload.subdata(in: offset ..< min(offset + 64 * 1_024, payload.count)))
            }
            events.completed(nil)
        }
        #expect(try await executor(driver, limit: payload.count).execute(request).body == payload)
    }
}

// MARK: - Per-test fixtures; no static mutable state, global URLProtocol handler, sleeps or real URLs fetched.

/// Builds a syntactically valid URL at a reserved .invalid origin; the fixture never resolves it.
private func fixtureURL(_ text: String = "https://fixture.invalid/path") throws -> URL {
    try #require(URL(string: text))
}

/// Constructs caller values with bounded fixtures; preserves canaries only in local test request material.
private func fixtureRequest(
    url: String = "https://fixture.invalid/path", method: String = "GET",
    headers: [String: String] = [:], body: Data? = nil
) throws -> UpstreamHTTPRequest {
    UpstreamHTTPRequest(method: method, url: try fixtureURL(url), headers: headers, body: body)
}

/// Creates only sanitized response metadata; exact length defaults to known nonnegative framing.
private func head(
    url: URL, status: Int = 200, length: Int64 = -1, exact: Bool = true, expectsBody: Bool = true
) -> UpstreamHTTPResponseHead {
    UpstreamHTTPResponseHead(
        status: status, origin: UpstreamHTTPOrigin(url: url), expectedLength: length,
        lengthIsExact: exact && length >= 0, expectsBody: expectsBody
    )
}

/// Sends an accepted head through the SAME callback boundary as the native delegate.
private func sendHead(
    _ events: UpstreamHTTPTransferEvents, url: URL, status: Int = 200,
    length: Int64 = -1, exact: Bool = true, expectsBody: Bool = true
) {
    #expect(events.response(head(url: url, status: status, length: length, exact: exact, expectsBody: expectsBody)))
}

/// Injects fixtures per executor; neither defaults nor tests use shared URLSession/URLProtocol state.
private func executor(
    _ driver: any UpstreamHTTPTaskDriving, deadlines: ManualDeadlines = ManualDeadlines(),
    limit: Int = 1_024, policy: UpstreamHTTPPolicy = .init()
) -> URLSessionUpstreamHTTP {
    URLSessionUpstreamHTTP(maxDownloadBytes: limit, policy: policy, driver: driver, deadlines: deadlines)
}

/// Asserts a typed failure without printing an unexpected raw error (which might itself contain credentials).
private func expectFailure(
    _ expected: UpstreamHTTPTransportError, operation: () async throws -> UpstreamHTTPResponse
) async {
    do { _ = try await operation(); Issue.record("expected transport failure") }
    catch let actual as UpstreamHTTPTransportError { #expect(actual == expected) }
    catch { Issue.record("unexpected error type; raw error deliberately not printed") }
}

/// Asserts CancellationError distinctly from a network error or successful partial response.
private func expectCancellation(operation: () async throws -> UpstreamHTTPResponse) async {
    do { _ = try await operation(); Issue.record("expected CancellationError") }
    catch is CancellationError { }
    catch { Issue.record("cancellation returned unexpected error type") }
}

/// Asserts a synchronous pure-core failure, permitting direct post-throw byte-buffer inspection.
private func expectSynchronousFailure(_ expected: UpstreamHTTPTransportError, operation: () throws -> Void) {
    do { try operation(); Issue.record("expected synchronous transport failure") }
    catch let actual as UpstreamHTTPTransportError { #expect(actual == expected) }
    catch { Issue.record("unexpected synchronous error type") }
}

/// Records suspended handles per test. Normal factories emit no callbacks/network I/O; an explicitly
/// injected factory script may emit invalidation or out-of-contract response events for defensive tests.
private final class CallbackDriver: UpstreamHTTPTaskDriving {
    private struct State: Sendable {
        var handles: [CallbackHandle] = []
        var cleanupRequested = false
    }
    private let storage = UpstreamHTTPMutex(State())
    private let automaticallyInvalidates: Bool
    private let cancelCurrentTaskDuringCreation: Bool
    private let cancelAndCleanupBeforePublication: Bool
    private let factoryScript: (@Sendable (URLRequest, CallbackHandle) -> Void)?
    private let script: @Sendable (URLRequest, UpstreamHTTPTransferEvents) -> Void
    let started: AsyncStream<CallbackHandle>
    private let startedContinuation: AsyncStream<CallbackHandle>.Continuation
    let teardownRequested: AsyncStream<Void>
    private let teardownContinuation: AsyncStream<Void>.Continuation

    /// A single-element latch prevents the test fixture from introducing an unbounded producer queue.
    init(
        automaticallyInvalidates: Bool = true, cancelCurrentTaskDuringCreation: Bool = false,
        cancelAndCleanupBeforePublication: Bool = false,
        factoryScript: (@Sendable (URLRequest, CallbackHandle) -> Void)? = nil,
        script: @escaping @Sendable (URLRequest, UpstreamHTTPTransferEvents) -> Void
    ) {
        self.automaticallyInvalidates = automaticallyInvalidates
        self.cancelCurrentTaskDuringCreation = cancelCurrentTaskDuringCreation
        self.cancelAndCleanupBeforePublication = cancelAndCleanupBeforePublication
        self.factoryScript = factoryScript
        self.script = script
        let pair = AsyncStream<CallbackHandle>.makeStream(bufferingPolicy: .bufferingNewest(1))
        started = pair.stream
        startedContinuation = pair.continuation
        let teardown = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        teardownRequested = teardown.stream
        teardownContinuation = teardown.continuation
    }

    /// Returns a snapshot of fixture-created tasks, never a mutable global registry.
    var handles: [CallbackHandle] { storage.withLock { $0.handles } }

    /// Records a permanent fixture-cleanup obligation under the publication lock. Acknowledgements
    /// happen outside the lock and are idempotent, including when cleanup and publication race.
    func requestCleanup() {
        let published = storage.withLock { state in
            state.cleanupRequested = true
            return state.handles
        }
        for handle in published { handle.acknowledgeInvalidation() }
    }

    /// Creates a suspended callback-only handle; optional cancellation tests the installation window.
    func makeTask(
        request: URLRequest, policy: UpstreamHTTPPolicy, events: UpstreamHTTPTransferEvents
    ) -> any UpstreamHTTPTaskHandle {
        let script = self.script
        let ready = startedContinuation
        let teardown = teardownContinuation
        let handle = CallbackHandle(
            events: events, automaticallyInvalidates: automaticallyInvalidates,
            onInvalidationRequested: { _ = teardown.yield(()) }
        ) { handle in
            script(request, events)
            ready.yield(handle)
        }
        if cancelAndCleanupBeforePublication {
            withUnsafeCurrentTask { $0?.cancel() }
            requestCleanup()
        }
        let cleanup = storage.withLock { state in
            state.handles.append(handle)
            return state.cleanupRequested
        }
        if cleanup { handle.acknowledgeInvalidation() }
        if cancelCurrentTaskDuringCreation { withUnsafeCurrentTask { $0?.cancel() } }
        // Deliberately runs outside fixture locks and before the core can publish this returned handle.
        factoryScript?(request, handle)
        return handle
    }

    /// Ends the latch when its owning test fixture disappears.
    deinit { startedContinuation.finish(); teardownContinuation.finish() }
}

/// Models thread-safe resume/cancel/invalidation with no unchecked Sendable annotations in test fixtures.
private final class CallbackHandle: UpstreamHTTPTaskHandle {
    struct Snapshot: Sendable {
        var resumeInvocations = 0
        var resumeCalls = 0
        var invalidationCalls = 0
        var cancelRequested = false
        var acknowledged = false
    }
    private let storage = UpstreamHTTPMutex(Snapshot())
    let events: UpstreamHTTPTransferEvents
    private let automaticallyInvalidates: Bool
    private let onInvalidationRequested: @Sendable () -> Void
    private let onResume: @Sendable (CallbackHandle) -> Void

    /// Keeps callbacks instance-owned, using the production core's same event contracts.
    init(
        events: UpstreamHTTPTransferEvents, automaticallyInvalidates: Bool,
        onInvalidationRequested: @escaping @Sendable () -> Void,
        onResume: @escaping @Sendable (CallbackHandle) -> Void
    ) {
        self.events = events
        self.automaticallyInvalidates = automaticallyInvalidates
        self.onInvalidationRequested = onInvalidationRequested
        self.onResume = onResume
    }

    /// Obtains immutable lifecycle evidence without exposing synchronized mutable state.
    var snapshot: Snapshot { storage.withLock { $0 } }

    /// A cancelled suspended handle cannot be revived; invokes the fixture only once and outside the lock.
    func resume() {
        let shouldRun = storage.withLock { state in
            state.resumeInvocations += 1 // distinguish forbidden terminal calls from suppressed activity
            guard state.invalidationCalls == 0, !state.acknowledged, state.resumeCalls == 0 else { return false }
            state.resumeCalls += 1
            return true
        }
        if shouldRun { onResume(self) }
    }

    /// Separates cancellation request from acknowledgement; tests can retain admission until manual teardown.
    func invalidate(cancel: Bool) {
        storage.withLock { state in
            state.invalidationCalls += 1
            state.cancelRequested = state.cancelRequested || cancel
        }
        onInvalidationRequested()
        if automaticallyInvalidates { acknowledgeInvalidation() }
    }

    /// Acknowledges teardown exactly once, outside the custody lock, just like the native invalidation delegate.
    func acknowledgeInvalidation(error: UpstreamHTTPTransportError? = nil) {
        let shouldAcknowledge = storage.withLock { state in
            guard !state.acknowledged else { return false }
            state.acknowledged = true
            return true
        }
        if shouldAcknowledge { events.invalidated(error) }
    }
}

/// Closed fixture scenarios force native-effect order after the core's registration/start-commit decision.
enum ResumeEffectOrder: Sendable {
    case cancellationBeforeResume, resumeBeforeCancellation
}

/// One owned handle and one single-element completion latch; no work queue, timer, blocking wait or globals.
/// Self-cancellation at the resume effect boundary is the deterministic hook, not a production ordering fence.
private final class ResumeEffectDriver: UpstreamHTTPTaskDriving {
    private struct State: Sendable {
        var handle: ResumeEffectHandle?
        var cleanupRequested = false
    }
    private let storage = UpstreamHTTPMutex(State())
    private let order: ResumeEffectOrder
    private let cancelAndCleanupBeforePublication: Bool
    private let script: @Sendable (URLRequest, UpstreamHTTPTransferEvents) -> Void
    let settled: AsyncStream<Void>
    private let settledContinuation: AsyncStream<Void>.Continuation

    /// Configures one immutable scenario; the stream stores at most one observation, never response Data.
    init(
        order: ResumeEffectOrder, cancelAndCleanupBeforePublication: Bool = false,
        script: @escaping @Sendable (URLRequest, UpstreamHTTPTransferEvents) -> Void
    ) {
        self.order = order
        self.cancelAndCleanupBeforePublication = cancelAndCleanupBeforePublication
        self.script = script
        let pair = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        settled = pair.stream
        settledContinuation = pair.continuation
    }

    /// Exposes only the single fixture-owned handle after its payload-free settled observation.
    var handle: ResumeEffectHandle? { storage.withLock { $0.handle } }

    /// Cleanup is sticky across publication, not a one-shot optional-handle snapshot. The same lock
    /// protects its obligation and handle custody; native-style acknowledgement stays outside it.
    func requestCleanup() {
        let published = storage.withLock { state in
            state.cleanupRequested = true
            return state.handle
        }
        published?.acknowledgeInvalidation()
    }

    /// Creates a suspended handle without callbacks. Only resume may exercise the effect-order hook.
    func makeTask(
        request: URLRequest, policy: UpstreamHTTPPolicy, events: UpstreamHTTPTransferEvents
    ) -> any UpstreamHTTPTaskHandle {
        let ready = settledContinuation
        let script = self.script
        let newHandle = ResumeEffectHandle(events: events, order: order, script: { script(request, events) }) {
            ready.yield(())
            ready.finish()
        }
        if cancelAndCleanupBeforePublication {
            withUnsafeCurrentTask { $0?.cancel() }
            requestCleanup()
        }
        let publication = storage.withLock { state -> (ResumeEffectHandle, Bool, Bool) in
            if let existing = state.handle { return (existing, false, state.cleanupRequested) }
            state.handle = newHandle
            return (newHandle, true, state.cleanupRequested)
        }
        #expect(publication.1, "single-handle effect-order fixture was unexpectedly reused")
        if publication.2 { publication.0.acknowledgeInvalidation() }
        return publication.0
    }

    /// Finishes the finite latch when its fixture is discarded.
    deinit { settledContinuation.finish() }
}

/// Records actual fixture effect application separately from entering the resume witness. All state is
/// synchronized; cancellation hooks, scripts, latch publication and acknowledgement run outside its lock.
private final class ResumeEffectHandle: UpstreamHTTPTaskHandle {
    enum Effect: Sendable, Equatable {
        case resumeApplied, resumeSuppressed, cancellationApplied, finishApplied, acknowledged
    }
    struct Snapshot: Sendable {
        var resumeInvocations = 0
        var scriptStarts = 0
        var invalidationCalls = 0
        var cancelRequested = false
        var acknowledged = false
        var effects: [Effect] = [] // at most resume-or-suppression, one invalidation and one acknowledgement
    }
    private let storage = UpstreamHTTPMutex(Snapshot())
    private let events: UpstreamHTTPTransferEvents
    private let order: ResumeEffectOrder
    private let script: @Sendable () -> Void
    private let onSettled: @Sendable () -> Void

    /// Stores immutable scenario callbacks and creates no native or asynchronous work.
    init(
        events: UpstreamHTTPTransferEvents, order: ResumeEffectOrder,
        script: @escaping @Sendable () -> Void, onSettled: @escaping @Sendable () -> Void
    ) {
        self.events = events
        self.order = order
        self.script = script
        self.onSettled = onSettled
    }

    /// Returns a value snapshot so assertions never race mutable effect-order evidence.
    var snapshot: Snapshot { storage.withLock { $0 } }

    /// Runs once after registration. A synchronous current-task cancellation re-enters the core's onCancel
    /// handler and applies this handle's invalidate witness before returning; neither lock is held here.
    /// The other scenario starts its script first. The latch fires only after the selected order is complete.
    func resume() {
        let first = storage.withLock { state in
            state.resumeInvocations += 1
            return state.resumeInvocations == 1
        }
        guard first else { return }
        if case .cancellationBeforeResume = order { withUnsafeCurrentTask { $0?.cancel() } }
        let start = storage.withLock { state in
            guard state.invalidationCalls == 0, !state.acknowledged else {
                state.effects.append(.resumeSuppressed)
                return false
            }
            state.scriptStarts = 1
            state.effects.append(.resumeApplied)
            return true
        }
        if start { script() }
        if case .resumeBeforeCancellation = order { withUnsafeCurrentTask { $0?.cancel() } }
        #expect(Task.isCancelled, "effect-order hook must run in its owning cancelled child task")
        onSettled()
    }

    /// Records one applied cancellation/invalidation, but withholds acknowledgement until the test releases it.
    func invalidate(cancel: Bool) {
        storage.withLock { state in
            guard state.invalidationCalls == 0 else { return }
            state.invalidationCalls = 1
            state.cancelRequested = cancel
            state.effects.append(cancel ? .cancellationApplied : .finishApplied)
        }
    }

    /// Confirms fixture teardown once and then calls the real core invalidation event outside the lock.
    func acknowledgeInvalidation() {
        let acknowledge = storage.withLock { state in
            guard !state.acknowledged else { return false }
            state.acknowledged = true
            state.effects.append(.acknowledged)
            return true
        }
        if acknowledge { events.invalidated(nil) }
    }
}

/// Manual per-test monotonic clock boundary. Index zero is headers; index one is the resource deadline.
private final class ManualDeadlines: UpstreamHTTPDeadlineScheduling {
    private let storage = UpstreamHTTPMutex<[ManualDeadline]>([])
    private let fireImmediatelyAtIndex: Int?

    /// Optional immediate firing deterministically exercises publication/installation races.
    init(fireImmediatelyAtIndex: Int? = nil) { self.fireImmediatelyAtIndex = fireImmediatelyAtIndex }

    /// Returns a bounded-by-test snapshot of deadlines; no native timer is scheduled.
    var tokens: [ManualDeadline] { storage.withLock { $0 } }

    /// Publishes a manual token, then optionally fires while the core is still installing that token.
    func schedule(after seconds: TimeInterval, action: @escaping @Sendable () -> Void) -> any UpstreamHTTPDeadlineToken {
        let timer = ManualDeadline(seconds: seconds, action: action)
        let index = storage.withLock { tokens in
            let index = tokens.count
            tokens.append(timer)
            return index
        }
        if index == fireImmediatelyAtIndex { timer.fire() }
        return timer
    }
}

/// Thread-safe manual timer can deliberately simulate a stale callback delivered after cancellation.
private final class ManualDeadline: UpstreamHTTPDeadlineToken {
    private struct State: Sendable { var cancelled = false; var fired = false }
    private let storage = UpstreamHTTPMutex(State())
    let seconds: TimeInterval
    private let action: @Sendable () -> Void

    /// Captures a finite fixture deadline without reading wall-clock time.
    init(seconds: TimeInterval, action: @escaping @Sendable () -> Void) {
        self.seconds = seconds
        self.action = action
    }

    /// Exposes cancellation evidence without racing deadline delivery.
    var isCancelled: Bool { storage.withLock { $0.cancelled } }

    /// Cancels idempotently; a forced stale fire is still possible by design.
    func cancel() { storage.withLock { $0.cancelled = true } }

    /// Fires at most once outside the lock; the core, not this token, must defeat stale callback races.
    func fire(evenIfCancelled: Bool = false) {
        let shouldFire = storage.withLock { state in
            guard !state.fired, evenIfCancelled || !state.cancelled else { return false }
            state.fired = true
            return true
        }
        if shouldFire { action() }
    }
}
