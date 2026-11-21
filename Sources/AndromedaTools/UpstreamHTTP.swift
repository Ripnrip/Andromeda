import Foundation

/// An already-materialized request. Callers must bound decoding/encoding before creating it.
public struct UpstreamHTTPRequest: Sendable, Equatable {
    public let method: String
    public let url: URL
    public let headers: [String: String]
    public let body: Data?

    /// Stores request values without copying or silently truncating the body.
    public init(method: String, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

/// A complete, bounded HTTP response; transport failures never return a partial response.
public struct UpstreamHTTPResponse: Sendable, Equatable {
    public let status: Int
    public let body: Data

    /// Stores a complete response. Status interpretation/redaction remain the caller's responsibility.
    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// Executes host-side HTTP calls. Broker doubles retain the existing injection boundary.
public protocol UpstreamHTTPExecuting: Sendable {
    /// Returns the entire bounded body or throws; cancellation is not a partial success.
    func execute(_ request: UpstreamHTTPRequest) async throws -> UpstreamHTTPResponse
}

/// Local transport budgets, not permission to invoke arbitrary resources or operations.
/// Validation occurs at execute entry to preserve the existing nonthrowing initializer.
public struct UpstreamHTTPPolicy: Sendable, Equatable {
    public let maxRequestBytes: Int
    public let maxHeaderFields: Int
    public let maxConcurrentRequests: Int
    public let requestTimeoutSeconds: TimeInterval
    public let resourceTimeoutSeconds: TimeInterval

    /// Defaults to 1 MiB request bytes, 64 fields, four admitted operations, and 30/60 seconds.
    /// Request bytes include UTF-8 method, absolute URL, header names/values/framing, and body.
    /// Request timeout is both an absolute response-header deadline and Foundation's idle timeout.
    /// Resource timeout is an absolute transfer deadline; native invalidation acknowledgement is
    /// deliberately awaited after either deadline (it is NOT a hard wall-clock teardown guarantee).
    public init(
        maxRequestBytes: Int = 1_024 * 1_024,
        maxHeaderFields: Int = 64,
        maxConcurrentRequests: Int = 4,
        requestTimeoutSeconds: TimeInterval = 30,
        resourceTimeoutSeconds: TimeInterval = 60
    ) {
        self.maxRequestBytes = maxRequestBytes
        self.maxHeaderFields = maxHeaderFields
        self.maxConcurrentRequests = maxConcurrentRequests
        self.requestTimeoutSeconds = requestTimeoutSeconds
        self.resourceTimeoutSeconds = resourceTimeoutSeconds
    }

    /// Rejects invalid or impractical budgets before admission, timers, or session creation.
    func validate(maxDownloadBytes: Int) throws(UpstreamHTTPTransportError) {
        guard (1 ... 64 * 1_024 * 1_024).contains(maxDownloadBytes) else {
            throw .invalidConfiguration(.downloadBytes)
        }
        guard (1 ... 8 * 1_024 * 1_024).contains(maxRequestBytes) else {
            throw .invalidConfiguration(.requestBytes)
        }
        guard (1 ... 128).contains(maxHeaderFields) else {
            throw .invalidConfiguration(.headerFields)
        }
        guard (1 ... 32).contains(maxConcurrentRequests) else {
            throw .invalidConfiguration(.concurrency)
        }
        guard requestTimeoutSeconds.isFinite, requestTimeoutSeconds > 0,
            requestTimeoutSeconds <= 300
        else { throw .invalidConfiguration(.requestDeadline) }
        guard resourceTimeoutSeconds.isFinite, resourceTimeoutSeconds > 0,
            resourceTimeoutSeconds <= 300, resourceTimeoutSeconds >= requestTimeoutSeconds
        else { throw .invalidConfiguration(.resourceDeadline) }
    }
}

/// Closed, payload-free errors: no URL, header, body, NSError userInfo, or credential is retained.
public enum UpstreamHTTPTransportError: Error, Sendable, Equatable, LocalizedError {
    public enum ConfigurationField: Sendable, Equatable {
        case downloadBytes, requestBytes, headerFields, concurrency, requestDeadline, resourceDeadline
    }
    public enum RequestViolation: Sendable, Equatable {
        case url, method, headerSyntax, duplicateHeader, forbiddenHeader, tooManyHeaders
    }
    public enum Deadline: Sendable, Equatable {
        case responseHeaders, resource, foundation
    }
    case invalidConfiguration(ConfigurationField)
    case invalidRequest(RequestViolation)
    case requestTooLarge(limit: Int)
    case responseTooLarge(limit: Int)
    case busy
    case redirectDenied
    case authenticationDenied
    case invalidResponse
    case responseOriginMismatch
    case responseLengthMismatch
    case sessionInvalidated
    case cancelled
    case deadlineExceeded(Deadline)
    case networkFailure(code: Int?)

    /// Produces safe diagnostics even when the broker interpolates localizedDescription.
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Invalid upstream transport configuration."
        case .invalidRequest: "Invalid upstream HTTP request."
        case .requestTooLarge(let limit): "Upstream request exceeds the \(limit)-byte transport limit."
        case .responseTooLarge(let limit): "Upstream response exceeds the \(limit)-byte transport limit."
        case .busy: "Upstream transport is at its concurrency limit."
        case .redirectDenied: "Upstream redirects are disabled."
        case .authenticationDenied: "Upstream authentication challenge is not permitted."
        case .invalidResponse: "Upstream did not provide a valid final HTTP response."
        case .responseOriginMismatch: "Upstream response origin differs from the requested origin."
        case .responseLengthMismatch: "Upstream response length does not match its framing."
        case .sessionInvalidated: "Upstream session invalidated without a completed response."
        case .cancelled: "Upstream request cancelled."
        case .deadlineExceeded: "Upstream transport deadline exceeded."
        case .networkFailure(let code):
            code.map { "Upstream network failure (code \($0))." } ?? "Upstream network failure."
        }
    }

    /// Keeps only a Foundation URL-error number; unknown domains and userInfo are discarded.
    static func sanitizing(_ error: any Error) -> Self {
        let native = error as NSError
        guard native.domain == NSURLErrorDomain else { return .networkFailure(code: nil) }
        switch native.code {
        case NSURLErrorCancelled: return .cancelled
        case NSURLErrorTimedOut: return .deadlineExceeded(.foundation)
        default: return .networkFailure(code: native.code)
        }
    }
}

/// A bounded executor. Value copies share admission; independent instances do not share a global gate.
public struct URLSessionUpstreamHTTP: UpstreamHTTPExecuting {
    public let maxDownloadBytes: Int
    public let policy: UpstreamHTTPPolicy
    private let admission: UpstreamHTTPAdmission
    private let driver: any UpstreamHTTPTaskDriving
    private let deadlines: any UpstreamHTTPDeadlineScheduling

    /// Preserves URLSessionUpstreamHTTP(), init(maxDownloadBytes:), and the public byte-limit property.
    /// Invalid legacy values fail on execute rather than trapping in this nonthrowing initializer.
    /// A separate overload preserves references to init(maxDownloadBytes:) as a function value too.
    public init(maxDownloadBytes: Int = 8 * 1_024 * 1_024) {
        self.init(maxDownloadBytes: maxDownloadBytes, policy: .init())
    }

    /// Allows explicit policy injection while omitted policy uses the legacy initializer's safe defaults.
    public init(maxDownloadBytes: Int = 8 * 1_024 * 1_024, policy: UpstreamHTTPPolicy) {
        self.init(
            maxDownloadBytes: maxDownloadBytes, policy: policy,
            driver: UpstreamHTTPNativeDriver(), deadlines: UpstreamHTTPNativeDeadlines()
        )
    }

    /// Injects per-instance callback/task and deadline boundaries for deterministic, no-network tests.
    init(
        maxDownloadBytes: Int, policy: UpstreamHTTPPolicy,
        driver: any UpstreamHTTPTaskDriving, deadlines: any UpstreamHTTPDeadlineScheduling
    ) {
        self.maxDownloadBytes = maxDownloadBytes
        self.policy = policy
        self.driver = driver
        self.deadlines = deadlines
        self.admission = UpstreamHTTPAdmission(limit: policy.maxConcurrentRequests)
    }

    /// Validates before constructing URLRequest; rejects saturation without retaining queued requests.
    /// The admission permit survives cancellation/failure until the driver confirms session invalidation.
    public func execute(_ request: UpstreamHTTPRequest) async throws -> UpstreamHTTPResponse {
        try Task.checkCancellation()
        try policy.validate(maxDownloadBytes: maxDownloadBytes)
        guard admission.acquire() else { throw UpstreamHTTPTransportError.busy }
        defer { admission.release() }
        try Task.checkCancellation()
        // Bound concurrent request normalization too, not merely active URLSession tasks.
        let origin = try UpstreamHTTPValidation.validate(request, policy: policy)

        var native = URLRequest(url: request.url, cachePolicy: .reloadIgnoringLocalCacheData)
        native.httpMethod = request.method
        native.timeoutInterval = policy.requestTimeoutSeconds
        native.httpShouldHandleCookies = false
        for (name, value) in request.headers { native.setValue(value, forHTTPHeaderField: name) }
        native.httpBody = request.body

        let transfer = UpstreamHTTPTransfer(origin: origin, limit: maxDownloadBytes)
        let result = await transfer.run(request: native, policy: policy, driver: driver, deadlines: deadlines)
        // Cancellation observed during native teardown wins over a previously completed response.
        try Task.checkCancellation()
        switch result {
        case .success(let response): return response
        case .failure(.cancelled): throw CancellationError()
        case .failure(let error): throw error
        }
    }
}

/// HTTPS scheme/host/effective-port identity only; NOT a DNS, IP, SSRF, or typed-resource policy.
struct UpstreamHTTPOrigin: Sendable, Equatable {
    let host: String
    let port: Int

    /// Rejects URL userinfo/fragments and non-HTTPS schemes instead of silently rewriting them.
    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
            components.scheme?.lowercased() == "https",
            components.user == nil, components.password == nil, components.fragment == nil,
            let host = components.host, !host.isEmpty
        else { return nil }
        let port = components.port ?? 443
        guard (1 ... 65_535).contains(port) else { return nil }
        self.host = host.lowercased()
        self.port = port
    }
}

/// Pure request validation: nothing here creates a session or reads a credential store.
enum UpstreamHTTPValidation {
    /// Bounds caller-supplied request material and rejects transport identity/framing overrides.
    static func validate(
        _ request: UpstreamHTTPRequest, policy: UpstreamHTTPPolicy
    ) throws(UpstreamHTTPTransportError) -> UpstreamHTTPOrigin {
        guard request.headers.count <= policy.maxHeaderFields else {
            throw .invalidRequest(.tooManyHeaders)
        }
        var remaining = policy.maxRequestBytes
        try consume(request.body?.count ?? 0, remaining: &remaining, limit: policy.maxRequestBytes)
        try consume(request.method.utf8.count, remaining: &remaining, limit: policy.maxRequestBytes)
        try consume(request.url.absoluteString.utf8.count, remaining: &remaining, limit: policy.maxRequestBytes)
        guard let origin = UpstreamHTTPOrigin(url: request.url) else { throw .invalidRequest(.url) }
        guard !request.method.isEmpty, request.method.utf8.count <= 32, isToken(request.method),
            !["CONNECT", "TRACE"].contains(request.method.uppercased())
        else { throw .invalidRequest(.method) }
        var seen: Set<String> = []
        for (name, value) in request.headers {
            // Budget BEFORE lowercasing or any avoidable header copy.
            try consume(name.utf8.count, remaining: &remaining, limit: policy.maxRequestBytes)
            try consume(value.utf8.count, remaining: &remaining, limit: policy.maxRequestBytes)
            try consume(4, remaining: &remaining, limit: policy.maxRequestBytes) // ': ' plus CRLF
            guard isToken(name), !value.utf8.contains(where: { $0 < 32 && $0 != 9 || $0 == 127 }) else {
                throw .invalidRequest(.headerSyntax)
            }
            let normalized = name.lowercased()
            guard seen.insert(normalized).inserted else { throw .invalidRequest(.duplicateHeader) }
            // Prevent authority substitution, request smuggling, proxy credentials, and hop-by-hop framing.
            guard ![
                "host", "content-length", "transfer-encoding", "connection", "proxy-connection",
                "proxy-authorization", "trailer", "te", "upgrade", "expect",
            ].contains(normalized) else { throw .invalidRequest(.forbiddenHeader) }
        }
        try consume(4, remaining: &remaining, limit: policy.maxRequestBytes) // separator budget
        return origin
    }

    /// Uses subtraction rather than unchecked sums so even Int.max counts cannot overflow a budget.
    private static func consume(
        _ count: Int, remaining: inout Int, limit: Int
    ) throws(UpstreamHTTPTransportError) {
        guard count <= remaining else { throw .requestTooLarge(limit: limit) }
        remaining -= count
    }

    /// Accepts only nonempty ASCII HTTP tokens, never Unicode or control-character method/field names.
    private static func isToken(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.allSatisfy {
            switch $0 {
            case 48 ... 57, 65 ... 90, 97 ... 122, 33, 35 ... 39, 42, 43, 45, 46, 94 ... 96, 124, 126:
                true
            default: false
            }
        }
    }
}

/// Sanitized delegate metadata. Content length can be advisory when decoding changes representation.
struct UpstreamHTTPResponseHead: Sendable {
    let status: Int?
    let origin: UpstreamHTTPOrigin?
    let expectedLength: Int64
    let lengthIsExact: Bool
    let expectsBody: Bool
}

/// Pure, chunk-oriented collector shared by production callbacks and deterministic tests.
struct UpstreamHTTPCollector: Sendable {
    let origin: UpstreamHTTPOrigin
    let limit: Int
    private(set) var head: UpstreamHTTPResponseHead?
    private(set) var body = Data()

    /// Requires one final HTTP head with matching origin; rejects advertised oversized bodies early.
    mutating func receive(_ head: UpstreamHTTPResponseHead) throws(UpstreamHTTPTransportError) {
        guard self.head == nil, let status = head.status, (200 ... 599).contains(status) else {
            throw .invalidResponse
        }
        guard head.origin == origin else { throw .responseOriginMismatch }
        if head.expectsBody, head.expectedLength > Int64(limit) { throw .responseTooLarge(limit: limit) }
        self.head = head
    }

    /// Checks remaining capacity BEFORE appending a whole callback chunk. Equal-to-limit is legal.
    mutating func receive(_ chunk: Data) throws(UpstreamHTTPTransportError) {
        guard let head else { throw .invalidResponse }
        guard head.expectsBody || chunk.isEmpty else { throw .invalidResponse }
        guard chunk.count <= limit - body.count else { throw .responseTooLarge(limit: limit) }
        body.append(chunk)
    }

    /// Called only after native completion without an error; exact identity framing must match.
    mutating func finish() throws(UpstreamHTTPTransportError) -> UpstreamHTTPResponse {
        guard let head, let status = head.status else { throw .invalidResponse }
        if head.expectsBody, head.lengthIsExact, head.expectedLength >= 0,
            Int64(body.count) != head.expectedLength
        { throw .responseLengthMismatch }
        let response = UpstreamHTTPResponse(status: status, body: body)
        discard()
        return response
    }

    /// Drops collector-owned bytes on EVERY terminal path; no partial body enters a transport error.
    mutating func discard() { body = Data() }
}

/// Fail-fast per-executor admission. No waiting queue, no request payloads, no global mutable registry.
private final class UpstreamHTTPAdmission: Sendable {
    private let active = UpstreamHTTPMutex(0)
    private let limit: Int

    /// Stores the raw limit; execute validates it before attempting acquisition.
    init(limit: Int) { self.limit = limit }

    /// Atomically admits at most the validated number of transfers.
    func acquire() -> Bool {
        active.withLock { count in
            guard count < limit else { return false }
            count += 1
            return true
        }
    }

    /// Releases exactly one execute-owned permit after native invalidation or pre-start cancellation.
    func release() { active.withLock { $0 -= 1 } }
}

/// Synchronous application callbacks: no AsyncStream/Task per chunk and no application queue of Data.
/// Foundation's internal read-ahead/queued delegate buffers are opaque, NOT a proven process-memory bound.
struct UpstreamHTTPTransferEvents: Sendable {
    let response: @Sendable (UpstreamHTTPResponseHead) -> Bool
    let data: @Sendable (Data) -> Void
    let completed: @Sendable (UpstreamHTTPTransportError?) -> Void
    let rejected: @Sendable (UpstreamHTTPTransportError) -> Void
    let invalidated: @Sendable (UpstreamHTTPTransportError?) -> Void
}

/// A task boundary with explicit teardown acknowledgement, not an async timeout race facade.
protocol UpstreamHTTPTaskHandle: Sendable {
    /// Starts at most once; cancellation/invalidation already APPLIED to a suspended native task
    /// must prevent a later resume from reviving it. Logical cancellation selection is not that effect.
    func resume()
    /// Is idempotent and eventually calls events.invalidated after native work has stopped.
    func invalidate(cancel: Bool)
}

protocol UpstreamHTTPTaskDriving: Sendable {
    /// Creates a SUSPENDED task; no request/network traffic or response callbacks may precede resume.
    /// The core defensively tolerates factory-time invalidation and even out-of-contract completion;
    /// their native reachability is UNPROVED, not implied by the callback-only fixtures.
    /// Factory work is synchronous and nonthrowing; platform setup/normalization is not a hard CPU deadline.
    /// Invalidation of an unresumed task must still acknowledge teardown.
    func makeTask(
        request: URLRequest, policy: UpstreamHTTPPolicy, events: UpstreamHTTPTransferEvents
    ) -> any UpstreamHTTPTaskHandle
}

protocol UpstreamHTTPDeadlineToken: Sendable {
    /// Stops future delivery; a callback already in flight may still run and must be harmless.
    func cancel()
}

protocol UpstreamHTTPDeadlineScheduling: Sendable {
    /// Schedules one monotonic deadline with a thread-safe, idempotently cancellable ownership token.
    func schedule(after seconds: TimeInterval, action: @escaping @Sendable () -> Void) -> any UpstreamHTTPDeadlineToken
}

/// Locked custody of one transfer. All effects/continuation resumes happen OUTSIDE the state lock.
/// Native completion selects a result; only invalidation acknowledgement publishes it to execute.
final class UpstreamHTTPTransfer: Sendable {
    private enum Phase: Sendable, Equatable { case new, installing, running, invalidated }
    private struct Effects: Sendable {
        var handle: (any UpstreamHTTPTaskHandle)?
        var cancelNative = true
        var timers: [any UpstreamHTTPDeadlineToken] = []

        /// Executes idempotent native calls without holding the collector/lifecycle lock.
        func perform() {
            for timer in timers { timer.cancel() }
            handle?.invalidate(cancel: cancelNative)
        }
    }
    private struct State: Sendable {
        var phase: Phase = .new
        var collector: UpstreamHTTPCollector
        var result: Result<UpstreamHTTPResponse, UpstreamHTTPTransportError>?
        var continuation: CheckedContinuation<Result<UpstreamHTTPResponse, UpstreamHTTPTransportError>, Never>?
        var handle: (any UpstreamHTTPTaskHandle)?
        var headerTimer: (any UpstreamHTTPDeadlineToken)?
        var resourceTimer: (any UpstreamHTTPDeadlineToken)?

        /// Linearizes the first terminal event and removes all collector-owned bytes/deadline tokens.
        mutating func select(_ result: Result<UpstreamHTTPResponse, UpstreamHTTPTransportError>) -> Effects {
            guard self.result == nil, phase != .invalidated else { return Effects() }
            self.result = result
            collector.discard()
            let timers = [headerTimer, resourceTimer].compactMap { $0 }
            headerTimer = nil
            resourceTimer = nil
            let cancel: Bool
            switch result { case .success: cancel = false; case .failure: cancel = true }
            return Effects(handle: handle, cancelNative: cancel, timers: timers)
        }
    }
    private let state: UpstreamHTTPMutex<State>

    /// Creates only bounded value state; no native session exists until run installs its continuation.
    init(origin: UpstreamHTTPOrigin, limit: Int) {
        state = UpstreamHTTPMutex(State(collector: UpstreamHTTPCollector(origin: origin, limit: limit)))
    }

    /// Covers cancellation before continuation registration, during task creation, and during callbacks.
    func run(
        request: URLRequest, policy: UpstreamHTTPPolicy,
        driver: any UpstreamHTTPTaskDriving, deadlines: any UpstreamHTTPDeadlineScheduling
    ) async -> Result<UpstreamHTTPResponse, UpstreamHTTPTransportError> {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                start(request: request, policy: policy, driver: driver, deadlines: deadlines, continuation: continuation)
            }
        } onCancel: { self.reject(.cancelled) }
    }

    /// Registers ownership first, then installs cancellable deadlines and an unresumed native task.
    private func start(
        request: URLRequest, policy: UpstreamHTTPPolicy,
        driver: any UpstreamHTTPTaskDriving, deadlines: any UpstreamHTTPDeadlineScheduling,
        continuation: CheckedContinuation<Result<UpstreamHTTPResponse, UpstreamHTTPTransportError>, Never>
    ) {
        let early = state.withLock { state -> Result<UpstreamHTTPResponse, UpstreamHTTPTransportError>? in
            if let result = state.result {
                state.phase = .invalidated
                return result // cancelled before any native task could exist
            }
            state.continuation = continuation
            state.phase = .installing
            return nil
        }
        if let early { continuation.resume(returning: early); return }

        installTimer(deadlines.schedule(after: policy.requestTimeoutSeconds) { [weak self] in
            self?.expire(headers: true)
        }, headers: true)
        installTimer(deadlines.schedule(after: policy.resourceTimeoutSeconds) { [weak self] in
            self?.expire(headers: false)
        }, headers: false)
        let events = UpstreamHTTPTransferEvents(
            response: { self.receive($0) }, data: { self.receive($0) },
            completed: { self.complete($0) }, rejected: { self.reject($0) }, invalidated: { self.invalidated($0) }
        )
        let handle = driver.makeTask(request: request, policy: policy, events: events)
        let cancel = state.withLock { state in
            // A factory-time acknowledgement may have published the result and cleared custody.
            // Never retain its returned terminal handle or revive the terminal phase.
            guard state.phase != .invalidated else { return true }
            state.handle = handle
            state.phase = .running
            return state.result != nil
        }
        // Also tears down an orphan returned after invalidation; native calls remain outside the lock.
        if cancel { handle.invalidate(cancel: true) } else { handle.resume() }
        // Registration with no selected result is the logical start-commit point, not a native-effect
        // ordering fence. Later cancellation selects failure under the lock, then applies teardown
        // outside it: resume can reach the native task either before or after that cancellation effect.
        // An actual preceding native cancel/invalidation must prevent revival; Darwin proof remains
        // a separate gate. A start that wins this race makes no zero-transmission or rollback promise.
    }

    /// Closes timer-installation races: a terminal event can precede publication of its token.
    private func installTimer(_ timer: any UpstreamHTTPDeadlineToken, headers: Bool) {
        let cancel = state.withLock { state in
            guard state.result == nil, state.phase != .invalidated else { return true }
            if headers {
                guard state.collector.head == nil else { return true }
                state.headerTimer = timer
            } else { state.resourceTimer = timer }
            return false
        }
        if cancel { timer.cancel() }
    }

    /// Ignores an in-flight header timer once a head won the lock; timer cancellation alone is insufficient.
    private func expire(headers: Bool) {
        let effects = state.withLock { state -> Effects in
            if headers, state.collector.head != nil { return Effects() }
            return state.select(.failure(.deadlineExceeded(headers ? .responseHeaders : .resource)))
        }
        effects.perform()
    }

    /// Receives a response head synchronously and retires the response-header deadline only on acceptance.
    private func receive(_ head: UpstreamHTTPResponseHead) -> Bool {
        let update = state.withLock { state -> (Bool, Effects) in
            guard state.result == nil, state.phase != .invalidated else { return (false, Effects()) }
            do throws(UpstreamHTTPTransportError) {
                try state.collector.receive(head)
                let timers = state.headerTimer.map { [$0] } ?? []
                state.headerTimer = nil
                return (true, Effects(timers: timers))
            } catch { return (false, state.select(.failure(error))) }
        }
        update.1.perform()
        return update.0
    }

    /// Enforces chunk bounds inside the same lock as completion/cancellation, with no partial prefix append.
    private func receive(_ data: Data) {
        let effects = state.withLock { state -> Effects in
            guard state.result == nil, state.phase != .invalidated else { return Effects() }
            do throws(UpstreamHTTPTransportError) { try state.collector.receive(data); return Effects() }
            catch { return state.select(.failure(error)) }
        }
        effects.perform()
    }

    /// Treats midstream errors as failures. Success requires native completion AND collector framing checks.
    private func complete(_ error: UpstreamHTTPTransportError?) {
        let effects = state.withLock { state -> Effects in
            guard state.result == nil, state.phase != .invalidated else { return Effects() }
            if let error { return state.select(.failure(error)) }
            do throws(UpstreamHTTPTransportError) {
                let response = try state.collector.finish()
                return state.select(.success(response))
            }
            catch { return state.select(.failure(error)) }
        }
        effects.perform()
    }

    /// Records the first failure, clears bytes, and cancels the actual native task/session if installed.
    private func reject(_ error: UpstreamHTTPTransportError) {
        state.withLock { $0.select(.failure(error)) }.perform()
    }

    /// Breaks the session/delegate/event ownership cycle and resumes exactly once AFTER native teardown.
    /// Unexpected invalidation fails closed; even a selected success is rejected on invalidation error.
    private func invalidated(_ error: UpstreamHTTPTransportError?) {
        let final = state.withLock { state -> (
            CheckedContinuation<Result<UpstreamHTTPResponse, UpstreamHTTPTransportError>, Never>?,
            Result<UpstreamHTTPResponse, UpstreamHTTPTransportError>, Effects
        )? in
            guard state.phase != .invalidated else { return nil }
            var effects = Effects()
            if state.result == nil { effects = state.select(.failure(error ?? .sessionInvalidated)) }
            if let error, case .success? = state.result { state.result = .failure(error) }
            effects.handle = nil // already invalidated: never recursively invalidate from this callback
            let result = state.result ?? .failure(.sessionInvalidated)
            let continuation = state.continuation
            state.continuation = nil
            state.handle = nil
            state.result = nil
            state.phase = .invalidated
            return (continuation, result, effects)
        }
        guard let final else { return }
        final.2.perform()
        final.0?.resume(returning: final.1)
    }
}
