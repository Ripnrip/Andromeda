// Proposed new helper: Sources/AndromedaTools/UpstreamHTTPNative.swift.
import Dispatch
import Foundation

/// A macOS-14-compatible synchronous custody primitive (Synchronization.Mutex needs newer macOS).
/// SAFETY INVARIANT for @unchecked Sendable: value is private, every access is under this NSLock,
/// Value/Result are compiler-checked Sendable, and the synchronous closure cannot escape inout storage.
/// No suspension, continuation resume, or caller/native callback is performed while holding this lock.
/// This annotation wraps actual synchronized reference state, not a non-Sendable value-type payload.
final class UpstreamHTTPMutex<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    /// Takes exclusive custody of an initial Sendable value.
    init(_ value: Value) { self.value = value }

    /// Mutates custody synchronously; callers must not re-enter this same lock from the closure.
    func withLock<Result: Sendable>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

/// Creates one owned, ephemeral URLSession and one SUSPENDED data task per admitted operation.
/// A serial delegate queue processes entire Data chunks without an additional application Data queue.
/// Native read-ahead, response-header allocation and queued callback memory remain Foundation-owned;
/// this adapter does not establish a hard total-process or compressed-wire-byte memory bound.
struct UpstreamHTTPNativeDriver: UpstreamHTTPTaskDriving {
    /// Disables ambient cookie/cache/credential stores; does not read secrets or start a request here.
    func makeTask(
        request: URLRequest, policy: UpstreamHTTPPolicy, events: UpstreamHTTPTransferEvents
    ) -> any UpstreamHTTPTaskHandle {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpAdditionalHeaders = [:]
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = policy.requestTimeoutSeconds
        configuration.timeoutIntervalForResource = policy.resourceTimeoutSeconds
        configuration.httpMaximumConnectionsPerHost = 1
        let queue = OperationQueue()
        queue.name = "Andromeda.UpstreamHTTP.delegate"
        queue.maxConcurrentOperationCount = 1
        let delegate = UpstreamHTTPNativeDelegate(events: events, method: request.httpMethod ?? "GET")
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: queue)
        return UpstreamHTTPNativeTask(session: session, task: session.dataTask(with: request))
    }
}

/// Only immutable references to Foundation's documented thread-safe URLSession/task APIs cross threads.
/// The SDK must prove these Foundation references Sendable; no @preconcurrency or unchecked escape hatch.
private final class UpstreamHTTPNativeTask: UpstreamHTTPTaskHandle {
    private let session: URLSession
    private let task: URLSessionDataTask

    /// Retains native ownership until invalidation acknowledgement breaks the transfer's ownership cycle.
    init(session: URLSession, task: URLSessionDataTask) {
        self.session = session
        self.task = task
    }

    /// If native cancellation/invalidation was already applied to the suspended task, resume must not
    /// revive it. A logical cancellation may instead race and follow this call; no effect order is implied.
    /// Verify both native effect orders against the pinned Darwin SDK before adopting this draft.
    func resume() { task.resume() }

    /// Cancels the real task before invalidating the session; success also invalidates its owned session.
    /// execute does NOT release admission until didBecomeInvalidWithError has been delivered.
    func invalidate(cancel: Bool) {
        if cancel {
            task.cancel()
            session.invalidateAndCancel()
        } else {
            session.finishTasksAndInvalidate()
        }
    }
}

/// Immutable, compiler-checked Sendable delegate; mutable collector/lifecycle state is in the locked core.
/// This intentionally rejects ALL redirects, including same-origin redirects that could change a typed
/// resource/path or replay a credential-bearing method/body. There is no redirect-following policy knob.
private final class UpstreamHTTPNativeDelegate: NSObject, URLSessionDataDelegate, Sendable {
    private let events: UpstreamHTTPTransferEvents
    private let method: String

    /// Captures only Sendable callbacks and an immutable method, never raw credentials/error payloads.
    init(events: UpstreamHTTPTransferEvents, method: String) {
        self.events = events
        self.method = method
        super.init()
    }

    /// Decides response acceptance BEFORE body delivery; checks metadata without retaining header values.
    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        let http = response as? HTTPURLResponse
        let status = http?.statusCode
        let expectsBody = method.uppercased() != "HEAD" && status != 204 && status != 304
        let encoding = http?.value(forHTTPHeaderField: "Content-Encoding")?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Delivered Data can be decompressed. Never compare decoded size against an encoded length.
        // Native completion is still mandatory; actual delivered bytes are always bounded by the core.
        let exact = expectsBody && (encoding == nil || encoding == "identity")
            && http?.value(forHTTPHeaderField: "Transfer-Encoding") == nil
        let head = UpstreamHTTPResponseHead(
            status: status, origin: response.url.flatMap { UpstreamHTTPOrigin(url: $0) },
            expectedLength: response.expectedContentLength, lengthIsExact: exact, expectsBody: expectsBody
        )
        completionHandler(events.response(head) ? .allow : .cancel)
    }

    /// Delivers one entire native chunk synchronously; oversize rejection cancels the actual session.
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        events.data(data)
    }

    /// Forwards only sanitized failure classifications; no partial body or NSError text is included.
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        events.completed(error.map { UpstreamHTTPTransportError.sanitizing($0) })
    }

    /// Returns nil rather than a sanitized/rebuilt redirect: nothing is sent to ANY redirect target.
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
        events.rejected(.redirectDenied)
    }

    /// Leaves ordinary TLS trust evaluation intact; never supplies a stored credential/client certificate.
    func urlSession(
        _ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handle(challenge, completionHandler: completionHandler)
    }

    /// Applies the same no-ambient-auth rule to task-level HTTP/proxy/client-certificate challenges.
    func urlSession(
        _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handle(challenge, completionHandler: completionHandler)
    }

    /// Accepts only system server-trust validation, never permissive custom trust or credential fallback.
    private func handle(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            events.rejected(.authenticationDenied)
        }
    }

    /// Confirms native ownership teardown; the core then resumes execute and permits admission release.
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?) {
        events.invalidated(error.map { UpstreamHTTPTransportError.sanitizing($0) })
    }
}

/// DispatchTime is monotonic. These are finite, transfer-owned timers, not persistent background services.
struct UpstreamHTTPNativeDeadlines: UpstreamHTTPDeadlineScheduling {
    private let queue = DispatchQueue(label: "Andromeda.UpstreamHTTP.deadlines", qos: .utility)

    /// Starts one timer; callback races are resolved under the transfer's lock, not by timer cancellation.
    func schedule(after seconds: TimeInterval, action: @escaping @Sendable () -> Void) -> any UpstreamHTTPDeadlineToken {
        UpstreamHTTPNativeDeadline(queue: queue, seconds: seconds, action: action)
    }
}

/// SAFETY INVARIANT for @unchecked Sendable: source is immutable after init, configured and resumed
/// EXACTLY ONCE before publication; the only public operation is DispatchSource.cancel(), which is
/// thread-safe and idempotent. No Swift mutable state exists. An in-flight handler can survive cancel;
/// the locked core must ignore stale header deadlines and every post-terminal callback.
private final class UpstreamHTTPNativeDeadline: UpstreamHTTPDeadlineToken, @unchecked Sendable {
    private let source: any DispatchSourceTimer

    /// Configures then resumes before publication, avoiding suspended-source teardown races.
    init(queue: DispatchQueue, seconds: TimeInterval, action: @escaping @Sendable () -> Void) {
        source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + seconds, leeway: .milliseconds(10))
        source.setEventHandler(handler: action)
        source.resume()
    }

    /// Cancels idempotently; callbacks already in flight are intentionally not considered drained here.
    func cancel() { source.cancel() }

    /// Drops the native timer even if an owner forgot explicit cancellation on a pre-start path.
    deinit { source.cancel() }
}
