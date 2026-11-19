@testable import AndromedaSecrets
import Dispatch
import Foundation
import Testing

/// Controlled state tests complement, rather than replace, the public cancellation
/// and real-dispatch deadline fixtures. Every runner is synthetic; never use .live.
@Suite("AndromedaSecrets.BoundedSecretLookupRaces")
struct BoundedSecretLookupRaceTests: Sendable {
    private static let reference = SecretReference(service: "synthetic-service", account: "synthetic-account")
    private static let canary = "SYNTHETIC-LATE-RESULT-NOT-A-CREDENTIAL"
    private static let timedOut = SecretProviderError.backendUnavailable("keychain lookup wait timed out")

    /// DispatchTime is quantized to the platform's monotonic ticks. A manual
    /// timeout must be representable, not a sub-tick duration that becomes zero.
    /// Advancing this clock consumes no wall time and must leave reuse a fresh cutoff.
    @Test("controlled clock cutoffs are future before and after manual advancement")
    func controlledClockCutoffs() {
        let clock = ControlledClock()
        let first = makeRequest(clock: clock)
        #expect(clock.now.uptimeNanoseconds < first.expiresAt.uptimeNanoseconds)
        clock.movePastCutoff()
        #expect(clock.now.uptimeNanoseconds >= first.expiresAt.uptimeNanoseconds)
        let second = makeRequest(clock: clock)
        #expect(clock.now.uptimeNanoseconds < second.expiresAt.uptimeNanoseconds)
    }

    /// The same caller performs its two public calls in sequence, with NO drain or
    /// retry between them. The old worker is held AFTER delivery, while the second
    /// call reserves the lane. Holding happens only on that synthetic dispatch
    /// worker; a two-second notice bound and ten-second gate failsafe bound cleanup.
    @Test("sequential success and error recovery release before delivery", arguments: [false, true])
    func sequentialDelivery(firstThrows: Bool) async {
        let tail = WorkerGate()
        let secondAdmission = Notice<Bool>()
        let admissions = Counter()
        let calls = Counter()
        let expected = SecretProviderError.notFound(service: "svc", account: "acct")
        let executor = BoundedSecretLookup(waitTimeout: .seconds(30), onBoundary: { boundary in
            switch boundary {
            case .admitted:
                if admissions.increment() == 2 { secondAdmission.send(true) }
            case .afterDelivery: tail.holdOnce()
            case .beforeClaim, .beforeTimerActivation: break
            }
        })
        let provider = MacOSKeychainSecretProvider(runner: .init { _, _ in
            let index = calls.increment()
            if firstThrows && index == 1 { throw expected }
            return Self.canary
        }, executor: executor)
        let caller: Task<String, any Error> = Task {
            if firstThrows {
                do {
                    _ = try await provider.secret(for: Self.reference)
                    Issue.record("expected first synthetic runner error")
                } catch let error as SecretProviderError {
                    #expect(error == expected)
                }
            } else {
                #expect(try await provider.secret(for: Self.reference) == Self.canary)
            }
            // Deliberately neither drain nor retry here.
            return try await provider.secret(for: Self.reference)
        }
        let failsafe = cancelAfterBound(caller)
        let reachedTail = await tail.entry.wait() == true
        let admittedSecond: Bool
        if reachedTail { admittedSecond = await secondAdmission.wait() == true }
        else { admittedSecond = false }
        #expect(reachedTail)
        #expect(admittedSecond)
        if admittedSecond { #expect(executor.snapshot == .admitted) }
        if !admittedSecond { caller.cancel() }
        tail.release()
        let result = await caller.result
        failsafe.cancel(); await failsafe.value
        if admittedSecond { assertSuccess(result) }
        await executor.drainForTesting()
        #expect(executor.snapshot == .idle)
        #expect(!tail.usedFailsafe)
        if admittedSecond { #expect(calls.value == 2) }
    }

    /// Unlike a pre-canceled Task.checkCancellation test, this drives the actual
    /// canceledBeforeInstall branch. A rejected installation must resume exactly
    /// once and skip submit, leaving no admission, native invocation, or timer.
    @Test("cancellation before continuation installation skips submission")
    func beforeContinuationInstallation() async {
        let clock = ControlledClock()
        let timers = TimerBook()
        let calls = Counter()
        let executor = makeLane(clock: clock, timers: timers)
        let request = makeRequest(clock: clock)
        request.cancel()
        #expect(request.phaseForTesting == .canceledBeforeInstall)
        let bridge = Bridge(request: request)
        let accepted = await bridge.installed.wait()
        #expect(accepted == false)
        // Mirror the production install guard. Even an unexpected accepted result
        // is submitted so that its caller is not intentionally left unjoined.
        if accepted == true { executor.submit(request: request, reference: Self.reference, runner: runner(calls)) }
        assertCanceled(await bridge.caller.result)
        await bridge.close()
        await executor.drainForTesting()
        #expect(request.phaseForTesting == .finished)
        #expect(!request.hasDeadlineForTesting)
        #expect(calls.value == 0)
        #expect(timers.count == 0)
        #expect(executor.snapshot == .idle)
        await assertReuse(executor)
    }

    /// Internal request/coordinator fixtures deliberately pause submission after
    /// install, or hold the queued dispatch worker before claim. Cancellation is
    /// invoked on Request, so these test first-state-winner custody independently
    /// of the public bridge's additional post-resume Task cancellation check.
    @Test("installed and admitted-before-claim cancellation skip native work", arguments: [true, false])
    func cancellationBeforeClaim(cancelBeforeSubmit: Bool) async {
        let clock = ControlledClock()
        let timers = TimerBook()
        let gate = WorkerGate()
        let calls = Counter()
        let executor = makeLane(clock: clock, timers: timers, onBoundary: { boundary in
            if case .beforeClaim = boundary { gate.holdOnce() }
        })
        let request = makeRequest(clock: clock)
        let bridge = Bridge(request: request)
        guard await bridge.installed.wait() == true else {
            gate.release(); await bridge.close(); await executor.drainForTesting()
            Issue.record("continuation installation did not complete within fixture bound")
            return
        }
        #expect(request.phaseForTesting == .waiting)
        if cancelBeforeSubmit {
            request.cancel()
            assertCanceled(await bridge.caller.result)
        }
        executor.submit(request: request, reference: Self.reference, runner: runner(calls))
        guard await gate.entry.wait() == true else {
            gate.release(); await bridge.close(); await executor.drainForTesting()
            Issue.record("synthetic pre-claim worker did not enter within fixture bound")
            return
        }
        #expect(executor.snapshot == .admitted)
        if !cancelBeforeSubmit { request.cancel() }
        assertCanceled(await bridge.caller.result)
        #expect(request.phaseForTesting == .finished)
        #expect(!request.hasDeadlineForTesting)
        #expect(executor.snapshot == .admitted)
        #expect(calls.value == 0)
        let rejected = MacOSKeychainSecretProvider(runner: runner(calls), executor: executor)
        let rejectedCaller = Task { try await rejected.secret(for: Self.reference) }
        let rejectedFailsafe = cancelAfterBound(rejectedCaller)
        assertFailure(await rejectedCaller.result, expected: .backendUnavailable("keychain lookup busy"))
        rejectedFailsafe.cancel(); await rejectedFailsafe.value
        #expect(timers.count == 1)
        timers.assertCanceledAndActivatedOnce()
        gate.release()
        await executor.drainForTesting()
        await bridge.close()
        #expect(!gate.usedFailsafe)
        #expect(calls.value == 0)
        #expect(executor.snapshot == .idle)
        await assertReuse(executor)
        timers.assertCanceledAndActivatedOnce()
    }

    /// Uses the SAME production attach/activate path with a controlled timer.
    /// Before-attachment cancellation rejects the source; between-attachment and
    /// activation cancellation detaches it. Both paths cancel and activate once.
    /// These observations prove coordinator custody, not OS timer deallocation.
    @Test("canceled timers are activated exactly once", arguments: [true, false])
    func timerAttachment(cancelBeforeAttachment: Bool) async {
        let clock = ControlledClock()
        let timers = TimerBook()
        let calls = Counter()
        let sawAttached = Counter()
        let request = makeRequest(clock: clock)
        let bridge = Bridge(request: request)
        let executor = BoundedSecretLookup(waitTimeout: ControlledClock.waitTimeout, now: { clock.now }, makeDeadline: { cutoff, handler in
            let timer = timers.make(cutoff, handler)
            if cancelBeforeAttachment { request.cancel() }
            return timer
        }, onBoundary: { boundary in
            if case .beforeTimerActivation = boundary, !cancelBeforeAttachment {
                if request.hasDeadlineForTesting { _ = sawAttached.increment() }
                request.cancel()
            }
        })
        guard await bridge.installed.wait() == true else {
            await bridge.close(); await executor.drainForTesting()
            Issue.record("timer fixture continuation installation exceeded bound")
            return
        }
        executor.submit(request: request, reference: Self.reference, runner: runner(calls))
        assertCanceled(await bridge.caller.result)
        await executor.drainForTesting()
        await bridge.close()
        #expect(sawAttached.value == (cancelBeforeAttachment ? 0 : 1))
        #expect(request.phaseForTesting == .finished)
        #expect(!request.hasDeadlineForTesting)
        #expect(calls.value == 0)
        #expect(timers.count == 1)
        #expect(timers.first?.canceledBeforeActivation == true)
        timers.assertCanceledAndActivatedOnce()
        // A queued event is adversarially delivered even after cancellation.
        timers.first?.fire()
        #expect(request.phaseForTesting == .finished)
        await assertReuse(executor)
        timers.assertCanceledAndActivatedOnce()
    }

    enum OutcomeOrder: Sendable, CaseIterable {
        case successThenCancel, cancelThenSuccess
        case successThenDeadline, deadlineThenSuccess
        case cancelThenDeadlineThenSuccess, deadlineThenCancelThenSuccess
        case cancelThenError, deadlineThenError
    }

    /// Finite, ordered transitions rather than sleep-based race guesses. One
    /// synchronous synthetic invocation returns once. Abandonment keeps capacity
    /// while it is active, drops late success/error canaries, and permits reuse
    /// after that worker returns. Delivering canceled timer callbacks and trying
    /// another finish explicitly checks that no second outcome can take custody.
    @Test("completion cancellation and deadline first-winner orders", arguments: OutcomeOrder.allCases)
    func outcomeOrders(order: OutcomeOrder) async {
        let clock = ControlledClock()
        let timers = TimerBook()
        let gate = WorkerGate()
        let calls = Counter()
        let returns = Counter()
        let executor = makeLane(clock: clock, timers: timers, onBoundary: { boundary in
            if case .afterDelivery = boundary { _ = returns.increment() }
        })
        let request = makeRequest(clock: clock)
        let bridge = Bridge(request: request)
        guard await bridge.installed.wait() == true else {
            gate.release(); await bridge.close(); await executor.drainForTesting()
            Issue.record("race fixture continuation installation exceeded bound")
            return
        }
        executor.submit(request: request, reference: Self.reference, runner: .init { _, _ in
            _ = calls.increment()
            gate.holdOnce()
            switch order {
            case .cancelThenError, .deadlineThenError:
                throw SecretProviderError.backendUnavailable(Self.canary)
            case .successThenCancel, .cancelThenSuccess, .successThenDeadline, .deadlineThenSuccess,
                 .cancelThenDeadlineThenSuccess, .deadlineThenCancelThenSuccess:
                return Self.canary
            }
        })
        guard await gate.entry.wait() == true else {
            gate.release(); await bridge.close(); await executor.drainForTesting()
            Issue.record("race fixture synthetic runner did not enter within bound")
            return
        }
        #expect(request.phaseForTesting == .running)
        #expect(executor.snapshot == .running)
        switch order {
        case .successThenCancel, .successThenDeadline:
            gate.release()
            assertSuccess(await bridge.caller.result)
            if case .successThenCancel = order { request.cancel() }
            else { clock.movePastCutoff(); timers.first?.fire() }
        case .cancelThenSuccess, .cancelThenError:
            request.cancel()
            assertCanceled(await bridge.caller.result)
            #expect(executor.snapshot == .running)
            gate.release()
        case .deadlineThenSuccess, .deadlineThenError:
            clock.movePastCutoff()
            timers.first?.fire()
            assertFailure(await bridge.caller.result, expected: Self.timedOut)
            #expect(executor.snapshot == .running)
            gate.release()
        case .cancelThenDeadlineThenSuccess:
            request.cancel()
            clock.movePastCutoff(); timers.first?.fire()
            assertCanceled(await bridge.caller.result)
            #expect(executor.snapshot == .running)
            gate.release()
        case .deadlineThenCancelThenSuccess:
            clock.movePastCutoff(); timers.first?.fire()
            request.cancel()
            assertFailure(await bridge.caller.result, expected: Self.timedOut)
            #expect(executor.snapshot == .running)
            gate.release()
        }
        await executor.drainForTesting()
        #expect(calls.value == 1)
        #expect(returns.value == 1)
        #expect(!gate.usedFailsafe)
        #expect(executor.snapshot == .idle)
        #expect(request.phaseForTesting == .finished)
        #expect(!request.hasDeadlineForTesting)
        #expect(!request.finish(.failure(SecretProviderError.backendUnavailable(Self.canary))))
        request.cancel()
        timers.first?.fire()
        timers.assertCanceledAndActivatedOnce()
        await bridge.close()
        await assertReuse(executor)
        timers.assertCanceledAndActivatedOnce()
    }

    /// The controlled deadline has NEVER fired when the native runner returns
    /// past the cutoff. The timestamp check alone must reject its late value.
    @Test("past-cutoff completion is rejected with delayed timer delivery")
    func delayedDeadlineDelivery() async {
        let clock = ControlledClock()
        let timers = TimerBook()
        let gate = WorkerGate()
        let calls = Counter()
        let executor = makeLane(clock: clock, timers: timers)
        let request = makeRequest(clock: clock)
        let bridge = Bridge(request: request)
        guard await bridge.installed.wait() == true else {
            gate.release(); await bridge.close(); await executor.drainForTesting()
            Issue.record("delayed-timer fixture installation exceeded bound")
            return
        }
        executor.submit(request: request, reference: Self.reference, runner: .init { _, _ in
            _ = calls.increment(); gate.holdOnce(); return Self.canary
        })
        guard await gate.entry.wait() == true else {
            gate.release(); await bridge.close(); await executor.drainForTesting()
            Issue.record("delayed-timer runner did not enter within fixture bound")
            return
        }
        clock.movePastCutoff()
        #expect(timers.first?.deliveries == 0)
        gate.release()
        assertFailure(await bridge.caller.result, expected: Self.timedOut)
        await executor.drainForTesting()
        #expect(timers.first?.deliveries == 0)
        #expect(calls.value == 1)
        #expect(!gate.usedFailsafe)
        #expect(!request.hasDeadlineForTesting)
        timers.assertCanceledAndActivatedOnce()
        timers.first?.fire()
        #expect(!request.finish(.success(Self.canary)))
        await bridge.close()
        await assertReuse(executor)
    }

    // MARK: - Small test-owned controls; no global handlers or live effects

    /// Installs the same tiny timing seams used by production, per private lane.
    private func makeLane(clock: ControlledClock, timers: TimerBook,
                          onBoundary: @escaping @Sendable (BoundedSecretLookup.Boundary) -> Void = { _ in }) -> BoundedSecretLookup {
        BoundedSecretLookup(waitTimeout: ControlledClock.waitTimeout, now: { clock.now },
                            makeDeadline: { cutoff, handler in timers.make(cutoff, handler) }, onBoundary: onBoundary)
    }

    /// Uses the lane's cutoff expression with a controlled monotonic clock.
    private func makeRequest(clock: ControlledClock) -> BoundedSecretLookup.Request {
        let instant = clock.now
        let request = BoundedSecretLookup.Request(expiresAt: instant + ControlledClock.waitTimeout, now: { clock.now })
        #expect(instant.uptimeNanoseconds < request.expiresAt.uptimeNanoseconds)
        return request
    }

    /// Returns only a fixed synthetic canary and a non-secret invocation count.
    private func runner(_ calls: Counter) -> MacOSKeychainSecretProvider.Runner {
        .init { _, _ in _ = calls.increment(); return Self.canary }
    }

    /// Fresh public call after return/skip proves reuse, not just an idle snapshot.
    /// The caller has a separate finite cancel failsafe because its timer is manual.
    private func assertReuse(_ executor: BoundedSecretLookup) async {
        let provider = MacOSKeychainSecretProvider(runner: .init { _, _ in Self.canary }, executor: executor)
        let caller = Task { try await provider.secret(for: Self.reference) }
        let failsafe = cancelAfterBound(caller)
        assertSuccess(await caller.result)
        failsafe.cancel(); await failsafe.value
        await executor.drainForTesting()
        #expect(executor.snapshot == .idle)
    }

    /// Independent finite caller cleanup; owners always cancel and join this task.
    private func cancelAfterBound(_ caller: Task<String, any Error>) -> Task<Void, Never> {
        Task {
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            caller.cancel()
        }
    }

    /// Never describes arbitrary injected errors or late result data in failures.
    private func assertSuccess(_ result: Result<String, any Error>) {
        switch result {
        case let .success(value):
            let exact = Array(value.utf8) == Array(Self.canary.utf8)
            #expect(exact)
        case .failure: Issue.record("expected synthetic success")
        }
    }

    /// Check a boolean so assertion diagnostics cannot describe a late canary error.
    private func assertCanceled(_ result: Result<String, any Error>) {
        switch result {
        case .success: Issue.record("unexpected late result delivery")
        case let .failure(error):
            let canceled = error is CancellationError
            #expect(canceled)
        }
    }

    /// Do not expose the actual injected error as a captured assertion operand.
    private func assertFailure(_ result: Result<String, any Error>, expected: SecretProviderError) {
        switch result {
        case .success: Issue.record("unexpected late result delivery")
        case let .failure(error):
            let matches = (error as? SecretProviderError) == expected
            #expect(matches)
        }
    }

    /// AsyncStream wait and sleeper are cancelable; task-group losers are joined.
    /// This helper never blocks an executor thread or spawns unbounded work.
    private struct Notice<Value: Sendable>: Sendable {
        private let stream: AsyncStream<Value>
        private let continuation: AsyncStream<Value>.Continuation

        init() {
            let pair = AsyncStream<Value>.makeStream(bufferingPolicy: .bufferingNewest(1))
            stream = pair.stream; continuation = pair.continuation
        }

        func send(_ value: Value) { continuation.yield(value) }

        func wait() async -> Value? {
            await withTaskGroup(of: Value?.self) { group in
                group.addTask {
                    var iterator = stream.makeAsyncIterator()
                    return await iterator.next()
                }
                group.addTask {
                    do { try await Task.sleep(for: .seconds(2)) } catch { return nil }
                    return nil
                }
                let value = await group.next() ?? nil
                group.cancelAll()
                return value
            }
        }
    }

    /// Test-only continuation owner. A separate cancelable sleeper ends waiting
    /// even if setup fails; close cancels the request and joins BOTH owned tasks.
    private struct Bridge: Sendable {
        let request: BoundedSecretLookup.Request
        let installed: Notice<Bool>
        let caller: Task<String, any Error>
        private let failsafe: Task<Void, Never>

        init(request: BoundedSecretLookup.Request) {
            self.request = request
            let notice = Notice<Bool>()
            installed = notice
            caller = Task {
                try await withCheckedThrowingContinuation { continuation in
                    notice.send(request.install(continuation))
                }
            }
            failsafe = Task {
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                request.cancel()
            }
        }

        func close() async {
            request.cancel()
            _ = await caller.result
            failsafe.cancel(); await failsafe.value
        }
    }

    /// SAFETY: all scalar clock/counter state is guarded by NSLock. These locked
    /// reference fixtures contain no global state, secrets, or unguarded mutation.
    private final class ControlledClock: @unchecked Sendable {
        // One millisecond is representable on Darwin's monotonic timebase; ten
        // nanoseconds can round to zero ticks. This is manual time, not a sleep.
        static let waitTimeout: DispatchTimeInterval = .milliseconds(1)
        private let lock = NSLock()
        private var instant = DispatchTime(uptimeNanoseconds: 1_000_000_000)
        var now: DispatchTime { lock.withLock { instant } }

        /// Advances by more than one fixture timeout while preserving monotonicity.
        func movePastCutoff() { lock.withLock { instant = instant + .milliseconds(2) } }
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() -> Int { lock.withLock { count += 1; return count } }
        var value: Int { lock.withLock { count } }
    }

    /// SAFETY: semaphore waits are finite and ONLY called from synthetic dispatch
    /// workers. Cooperative tests await Notice instead. Only the first hit parks;
    /// every setup failure explicitly releases, cancels/joins, and drains its lane.
    private final class WorkerGate: @unchecked Sendable {
        let entry = Notice<Bool>()
        private let semaphore = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var hits = 0
        private var failed = false
        var usedFailsafe: Bool { lock.withLock { failed } }

        func holdOnce() {
            let first = lock.withLock { hits += 1; return hits == 1 }
            guard first else { return }
            entry.send(true)
            if semaphore.wait(timeout: .now() + .seconds(10)) != .success {
                lock.withLock { failed = true }
            }
        }

        func release() { semaphore.signal() }
    }

    /// SAFETY: timer lifecycle arrays/counters are locked; immutable callbacks are
    /// invoked OUTSIDE locks, including adversarial post-cancel event delivery.
    /// The production callback weakly captures Request, not this test recorder.
    private final class TimerBook: @unchecked Sendable {
        private let lock = NSLock()
        private var timers: [ControlledTimer] = []
        var count: Int { lock.withLock { timers.count } }
        var first: ControlledTimer? { lock.withLock { timers.first } }

        func make(_ cutoff: DispatchTime, _ handler: @escaping @Sendable () -> Void) -> BoundedSecretLookup.Deadline {
            let timer = ControlledTimer(handler: handler)
            lock.withLock { timers.append(timer) }
            return .init(activate: { timer.activate() }, cancel: { timer.cancel() })
        }

        func assertCanceledAndActivatedOnce() {
            let snapshot = lock.withLock { timers }
            for timer in snapshot {
                #expect(timer.activations == 1)
                #expect(timer.cancellations == 1)
            }
        }
    }

    private final class ControlledTimer: @unchecked Sendable {
        private let lock = NSLock()
        private let handler: @Sendable () -> Void
        private var activationCount = 0
        private var cancellationCount = 0
        private var deliveryCount = 0
        private var canceledAtActivation = false
        var activations: Int { lock.withLock { activationCount } }
        var cancellations: Int { lock.withLock { cancellationCount } }
        var deliveries: Int { lock.withLock { deliveryCount } }
        var canceledBeforeActivation: Bool { lock.withLock { canceledAtActivation } }

        /// Stores only an immutable synthetic handler, never a secret result.
        init(handler: @escaping @Sendable () -> Void) { self.handler = handler }

        /// Records ordering as well as count; no system source is created here.
        func activate() {
            lock.withLock {
                activationCount += 1
                canceledAtActivation = cancellationCount > 0
            }
        }

        /// Counts the coordinator's cancellation call rather than ARC teardown.
        func cancel() { lock.withLock { cancellationCount += 1 } }

        /// Models an already-enqueued timer handler, including after cancellation.
        func fire() {
            lock.withLock { deliveryCount += 1 }
            handler()
        }
    }
}
