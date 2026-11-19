import Dispatch
import Foundation

#if canImport(OSLog)
import OSLog
#endif

/// One admitted native lookup, no admission waitlist, one bounded caller deadline.
/// A dispatch worker may remain blocked in Security indefinitely. Cancellation or
/// timeout DOES NOT free its slot or create a replacement worker. Subsequent
/// callers fail busy until the original work returns; there are no retries.
///
/// SAFETY invariant for this narrow legacy-reference wrapper:
/// - `activity` is read/written only under `lock`; the queues/timeout are immutable.
/// - Only the serial worker queue invokes runners, with one slot reserved first.
/// - No lock is held across lookup, suspension, diagnostics, or continuation resume.
/// - Native CF objects stay inside the runner; only Sendable values cross queues.
/// NSLock is used for the package's macOS 14 floor and portable fixture builds;
/// Synchronization.Mutex requires an availability/toolchain review before adoption.
/// This is not an unchecked annotation on a value type or arbitrary OS object.
final class BoundedSecretLookup: @unchecked Sendable {
    enum Activity: Sendable, Equatable {
        case idle
        case admitted
        case running
    }

    /// Internal finite fixture observations. Only worker boundaries may be held
    /// by synthetic tests; caller-side callbacks must be synchronous/nonblocking.
    enum Boundary: Sendable {
        case admitted
        case beforeClaim
        case beforeTimerActivation
        case afterDelivery
    }

    /// Narrow timer ownership seam, not a scheduler abstraction or public API.
    /// Production closures retain one Dispatch source; fixture closures record
    /// cancellation/activation without creating a system timer.
    struct Deadline: Sendable {
        let activate: @Sendable () -> Void
        let cancel: @Sendable () -> Void
    }

    /// Sole production lane; internal initializer injection isolates test fixtures.
    static let shared = BoundedSecretLookup()

    private let lock = NSLock()
    private var activity: Activity = .idle
    private let workerQueue = DispatchQueue(label: "andromeda.secrets.native-keychain.blocking")
    private let deadlineQueue: DispatchQueue
    private let waitTimeout: DispatchTimeInterval
    private let now: @Sendable () -> DispatchTime
    private let makeDeadline: @Sendable (DispatchTime, @escaping @Sendable () -> Void) -> Deadline
    private let onBoundary: @Sendable (Boundary) -> Void

    /// Sets a finite caller-wait policy, not a native execution timeout. Zero is
    /// valid (immediate abandonment); production fixes five seconds. This internal
    /// configuration seam does not accept an unlimited wait or a negative duration.
    init(
        waitTimeout: DispatchTimeInterval = .seconds(5),
        now: @escaping @Sendable () -> DispatchTime = { .now() },
        makeDeadline: (@Sendable (DispatchTime, @escaping @Sendable () -> Void) -> Deadline)? = nil,
        onBoundary: @escaping @Sendable (Boundary) -> Void = { _ in }
    ) {
        switch waitTimeout {
        case let .seconds(value), let .milliseconds(value), let .microseconds(value), let .nanoseconds(value):
            precondition(value >= 0, "secret lookup deadline must be nonnegative")
        case .never:
            preconditionFailure("secret lookup deadline must be finite")
        @unknown default:
            preconditionFailure("unsupported secret lookup deadline unit")
        }
        self.waitTimeout = waitTimeout
        self.now = now
        self.onBoundary = onBoundary
        let queue = DispatchQueue(label: "andromeda.secrets.native-keychain.deadline")
        self.deadlineQueue = queue
        self.makeDeadline = makeDeadline ?? { cutoff, handler in
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: cutoff)
            source.setEventHandler(handler: handler)
            return Deadline(activate: { source.activate() }, cancel: { source.cancel() })
        }
    }

    /// Exposes non-secret occupancy for tests/debugger inspection. Running may
    /// outlive its caller; the safe cancellation/timeout diagnostic distinguishes it.
    var snapshot: Activity {
        lock.withLock { activity }
    }

    /// Installs the cancellation-safe bridge. Cancellation is checked both before
    /// admission and after wakeup; errors remain unchanged unless this caller has
    /// been canceled. No task-group child waits for uninterruptible synchronous I/O.
    func lookup(reference: SecretReference, runner: MacOSKeychainSecretProvider.Runner) async throws -> String {
        try Task.checkCancellation()
        let request = Request(expiresAt: now() + waitTimeout, now: now)
        do {
            let value = try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await withCheckedThrowingContinuation { continuation in
                    guard request.install(continuation) else { return }
                    submit(request: request, reference: reference, runner: runner)
                }
            } onCancel: {
                request.cancel()
            }
            try Task.checkCancellation()
            return value
        } catch {
            try Task.checkCancellation()
            throw error
        }
    }

    /// Reserves before creating a timer or dispatching a worker. Rejected calls
    /// have neither a native work item nor a deadline source. Cancellation racing
    /// submission may reserve briefly, but `beginLookup` prevents a canceled claim.
    /// Internal visibility lets fixtures drive the installed-before-submit state.
    func submit(
        request: Request, reference: SecretReference, runner: MacOSKeychainSecretProvider.Runner
    ) {
        guard reserve() else {
            if request.finish(.failure(SecretProviderError.backendUnavailable("keychain lookup busy"))) {
                SecretLookupDiagnostics.emit(.busy)
            }
            return
        }
        onBoundary(.admitted)
        let deadline = makeDeadline(request.expiresAt) { [weak request] in request?.timeout() }
        request.installDeadline(deadline)
        onBoundary(.beforeTimerActivation)
        // Even if cancellation canceled this source during installation, it must
        // be activated exactly once before the last reference can be released.
        deadline.activate()
        workerQueue.async { [self, request, reference, runner] in
            onBoundary(.beforeClaim)
            guard request.beginLookup() else {
                release()
                return
            }
            markRunning()
            // The claim/native-invocation boundary is not atomic with cancellation
            // or deadline expiry: once the claim wins, lookup may still start.
            let result = Result { try runner.lookup(reference.service, reference.account) }
            // The synchronous effect has returned. Release THIS admission once,
            // before ordinary delivery can resume a caller making its next call.
            // No defer may release again after a newer caller reserves the lane.
            release()
            request.finishLookup(result)
            onBoundary(.afterDelivery)
            // A late value is discarded here; do not log, cache, or return it.
            // Swift String/Data do not promise cryptographic zeroization.
        }
    }

    /// Atomically admits one work item, with no queue of waiting lookups.
    private func reserve() -> Bool {
        let accepted = lock.withLock {
            guard activity == .idle else { return false }
            activity = .admitted
            return true
        }
        if accepted { SecretLookupDiagnostics.emit(.admitted) }
        return accepted
    }

    /// Records the successful work claim without reading any reference or value.
    private func markRunning() {
        lock.withLock { activity = .running }
        SecretLookupDiagnostics.emit(.started)
    }

    /// Releases capacity only when the queued work actually finishes or is skipped.
    /// Called once on each exclusive worker path, never by abandonment handlers.
    /// A delivered result has no outstanding native claim, even if the worker's
    /// non-native tail has not returned. There is intentionally no deferred release.
    private func release() {
        lock.withLock { activity = .idle }
        SecretLookupDiagnostics.emit(.workerReturned)
    }

    /// Test-only barrier for deterministic fixture cleanup after its gate is
    /// released. Never call this against live Security: there is no native-return
    /// deadline. Tests use runners with an independent finite blocking failsafe.
    func drainForTesting() async {
        await withCheckedContinuation { continuation in
            workerQueue.async { continuation.resume() }
        }
    }

    /// Exactly-once continuation custody; completed state retains no value/error.
    ///
    /// SAFETY invariant: all mutable state/deadline accesses are under this lock;
    /// the cutoff is immutable. Timer cancellation and continuation resumption
    /// occur after unlocking. Timer handlers weakly reference Request, avoiding a
    /// source/request cycle. Submit activates its source exactly once even if it
    /// was canceled before activation. There is no forced thread stop.
    /// Internal visibility is solely for controlled state fixtures, not clients.
    final class Request: @unchecked Sendable {
        private typealias Continuation = CheckedContinuation<String, any Error>

        private enum State {
            case awaitingInstall
            case waiting(Continuation)
            case running(Continuation)
            case canceledBeforeInstall
            case finished
        }

        enum Phase: Sendable, Equatable {
            case awaitingInstall, waiting, running, canceledBeforeInstall, finished
        }

        private let lock = NSLock()
        private var state: State = .awaitingInstall
        private var deadline: Deadline?
        private let now: @Sendable () -> DispatchTime
        let expiresAt: DispatchTime

        /// Captures a monotonic caller cutoff, independent of timer delivery latency.
        init(expiresAt: DispatchTime, now: @escaping @Sendable () -> DispatchTime = { .now() }) {
            self.expiresAt = expiresAt
            self.now = now
        }

        /// Non-secret fixture snapshots pin transition/custody, not timer ARC or
        /// OSLog behavior. No continuation or result escapes through these views.
        var phaseForTesting: Phase {
            lock.withLock {
                switch state {
                case .awaitingInstall: .awaitingInstall
                case .waiting: .waiting
                case .running: .running
                case .canceledBeforeInstall: .canceledBeforeInstall
                case .finished: .finished
                }
            }
        }

        var hasDeadlineForTesting: Bool {
            lock.withLock { deadline != nil }
        }

        /// Installs the sole continuation, delivering any early cancellation.
        /// The bridge invokes this exactly once; duplicate installation is a bug.
        func install(_ continuation: CheckedContinuation<String, any Error>) -> Bool {
            let accepted = lock.withLock {
                switch state {
                case .awaitingInstall:
                    state = .waiting(continuation)
                    return true
                case .canceledBeforeInstall:
                    state = .finished
                    return false
                case .waiting, .running, .finished:
                    preconditionFailure("secret lookup continuation installed more than once")
                }
            }
            if !accepted { continuation.resume(throwing: CancellationError()) }
            return accepted
        }

        /// Attaches a not-yet-activated source, or cancels it if already complete.
        /// Submit remains responsible for activation in both cases.
        func installDeadline(_ source: Deadline) {
            let accepted = lock.withLock {
                switch state {
                case .waiting, .running:
                    deadline = source
                    return true
                case .awaitingInstall, .canceledBeforeInstall, .finished:
                    return false
                }
            }
            if !accepted { source.cancel() }
        }

        /// Claims invocation only while waiting and before the cutoff. A deadline
        /// may still expire after this check, so a claim is not a native-call deadline.
        func beginLookup() -> Bool {
            guard now().uptimeNanoseconds < expiresAt.uptimeNanoseconds else {
                timeout()
                return false
            }
            return lock.withLock {
                guard case let .waiting(continuation) = state else { return false }
                state = .running(continuation)
                return true
            }
        }

        /// Rejects late native results even if the deadline queue has been delayed.
        /// It cannot force the async caller to run at an exact wall-clock instant.
        func finishLookup(_ result: Result<String, any Error>) {
            if now().uptimeNanoseconds >= expiresAt.uptimeNanoseconds {
                timeout()
            } else {
                _ = finish(result)
            }
        }

        /// Ends caller waiting without releasing the admitted native work slot.
        /// Early cancellation has a separate state so no continuation is lost.
        func cancel() {
            let early = lock.withLock {
                guard case .awaitingInstall = state else { return false }
                state = .canceledBeforeInstall
                return true
            }
            if early || finish(.failure(CancellationError())) {
                SecretLookupDiagnostics.emit(.callerCanceled)
            }
        }

        /// Reports a fixed safe deadline reason, not a fictitious native timeout.
        func timeout() {
            if finish(.failure(SecretProviderError.backendUnavailable("keychain lookup wait timed out"))) {
                SecretLookupDiagnostics.emit(.callerTimedOut)
            }
        }

        /// First waiting/running outcome wins. Late completions return false and
        /// retain nothing; cancellation after resume is checked by the async bridge.
        @discardableResult
        func finish(_ result: Result<String, any Error>) -> Bool {
            let resources: (Continuation, Deadline?)? = lock.withLock {
                switch state {
                case let .waiting(continuation), let .running(continuation):
                    state = .finished
                    let source = deadline
                    deadline = nil
                    return (continuation, source)
                case .awaitingInstall, .canceledBeforeInstall, .finished:
                    return nil
                }
            }
            guard let (continuation, source) = resources else { return false }
            source?.cancel()
            continuation.resume(with: result)
            return true
        }
    }
}

/// Typed, metadata-only operational events. No references, native objects,
/// values, arbitrary Error descriptions, or credential bytes enter OSLog.
private enum SecretLookupDiagnostics {
    enum Event: Sendable {
        case busy
        case admitted
        case started
        case callerCanceled
        case callerTimedOut
        case workerReturned
    }

    #if canImport(OSLog)
    private static let logger = Logger(subsystem: "Andromeda", category: "NativeKeychainLookup")
    #endif

    /// Emits bounded-work lifecycle evidence without configuring any service,
    /// persistent job, credential, or UI surface. Non-Apple fixtures are silent.
    static func emit(_ event: Event) {
        #if canImport(OSLog)
        switch event {
        case .busy: logger.debug("native-keychain admission=busy capacity=1")
        case .admitted: logger.debug("native-keychain admission=accepted capacity=1")
        case .started: logger.debug("native-keychain worker=running")
        case .callerCanceled: logger.debug("native-keychain caller=canceled native-interrupt=false")
        case .callerTimedOut: logger.warning("native-keychain caller=deadline native-interrupt=false")
        case .workerReturned: logger.debug("native-keychain worker=returned capacity=released")
        }
        #endif
    }
}
