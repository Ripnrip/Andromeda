@testable import AndromedaSecrets
import Dispatch
import Foundation
import Testing

#if os(macOS) && canImport(Security)
import LocalAuthentication
import Security
#endif

@Suite("AndromedaSecrets.NativeKeychainLookup")
struct NativeKeychainLookupTests: Sendable {
    private static let reference = SecretReference(service: "synthetic-service", account: "synthetic-account")
    private static let canary = "SYNTHETIC-NATIVE-LOOKUP-CANARY-NOT-A-CREDENTIAL"

    /// Exact names, including whitespace/punctuation, reach the injected adapter.
    /// This fixture does not call Security; query normalization would break it.
    @Test("exact service and account reach the pure adapter")
    func exactReference() throws {
        let service = " service:* \n"
        let account = " account:* \t"
        let adapter = NativeKeychainLookup.Adapter { query in
            #expect(query == .init(service: service, account: account))
            return .init(status: NativeKeychainLookup.Status.success.rawValue, payload: .data(Data(Self.canary.utf8)))
        }
        let value = try NativeKeychainLookup.lookup(service: service, account: account, adapter: adapter)
        #expect(value == Self.canary)
    }

    /// Native reads introduce no CLI framing newline. Compare UTF-8 bytes, not
    /// merely Swift's canonically equivalent String equality, to pin no trimming.
    /// Whitespace-only/newline-only, CR/LF, Unicode, and embedded NUL remain exact.
    @Test("nonempty UTF-8 data is returned byte-for-byte", arguments: [
        "synthetic-token", " token ", "\nsynthetic-token\r\n", "\n", " \t ", "clé-秘密", "synthetic\0token",
        "\u{FEFF}synthetic-token", "\u{0065}\u{0301}", "\u{FFFD}valid-stored-scalar",
    ])
    func preservesNonemptyUTF8(value: String) throws {
        let query = NativeKeychainLookup.Query(service: Self.reference.service, account: Self.reference.account)
        let result = try NativeKeychainLookup.decode(
            .init(status: 0, payload: .data(Data(value.utf8))), for: query
        )
        #expect(Array(result.utf8) == Array(value.utf8))
    }

    /// Every recognized status is exercised through a fixture adapter. Failure
    /// payloads deliberately carry a canary: status mapping must ignore all bytes.
    /// Locked/interaction-required is not falsely labeled missing or definitely locked.
    @Test("native statuses have distinct safe outcomes", arguments: NativeKeychainLookup.Status.allCases)
    func nativeStatusOutcomes(status: NativeKeychainLookup.Status) {
        let adapter = NativeKeychainLookup.Adapter { _ in
            .init(status: status.rawValue, payload: .data(Data(Self.canary.utf8)))
        }
        do {
            let result = try NativeKeychainLookup.lookup(
                service: Self.reference.service, account: Self.reference.account, adapter: adapter
            )
            #expect(status == .success)
            #expect(result == Self.canary)
        } catch let error as SecretProviderError {
            #expect(status != .success)
            #expect(error == expectedFailure(for: status))
            #expect(!error.localizedDescription.contains(Self.canary))
            #expect(!String(reflecting: error).contains(Self.canary))
        } catch {
            Issue.record("unexpected native error type")
        }
    }

    /// Success without a Data result is malformed backend output, not a missing
    /// reference. Neither nil nor an unexpected object is stringify-dumped.
    @Test("success requires a data result")
    func requiresDataResult() {
        assertDecodeFailure(.missing, expected: .backendUnavailable("keychain returned an unexpected data result"))
        assertDecodeFailure(.unexpectedType, expected: .backendUnavailable("keychain returned an unexpected data result"))
    }

    /// An empty found item is distinctly unusable. Injected/in-memory runners
    /// retain their old empty-string behavior; this is the live native data policy.
    @Test("empty native data fails closed without pretending missing")
    func emptyNativeData() {
        assertDecodeFailure(.data(Data()), expected: .backendUnavailable("keychain item contains empty data"))
    }

    /// Invalid leading byte, invalid continuation, truncation, and an overlong
    /// encoding must reject. Exact UTF-8 round-trip verification prevents the
    /// stdlib decoder's repair behavior from silently changing stored bytes.
    /// Also pins a stray continuation, encoded surrogate, and above-U+10FFFF.
    @Test("UTF-8 decoding rejects malformed byte sequences", arguments: [
        [UInt8(0xFF)], [UInt8(0xC3), 0x28], [UInt8(0xE2), 0x82], [UInt8(0xC0), 0xAF],
        [UInt8(0x80)], [UInt8(0xED), 0xA0, 0x80], [UInt8(0xF4), 0x90, 0x80, 0x80],
    ])
    func strictUTF8(bytes: [UInt8]) {
        assertDecodeFailure(.data(Data(bytes)), expected: .backendUnavailable("keychain item is not valid UTF-8"))
    }

    /// Unknown/future OSStatus values remain backend failures, even with a
    /// success-shaped data payload. The canary never appears in error messages.
    @Test("unknown statuses fail closed", arguments: [Int32(12), Int32.min])
    func unknownStatus(status: Int32) {
        let query = NativeKeychainLookup.Query(service: Self.reference.service, account: Self.reference.account)
        do {
            _ = try NativeKeychainLookup.decode(.init(status: status, payload: .data(Data(Self.canary.utf8))), for: query)
            Issue.record("expected unknown-status failure")
        } catch let error as SecretProviderError {
            #expect(error == .backendUnavailable("keychain lookup failed"))
            #expect(!error.localizedDescription.contains(Self.canary))
        } catch {
            Issue.record("unexpected native error type")
        }
    }

    #if os(macOS) && canImport(Security)
    /// Inspecting a CF-compatible dictionary is pure construction, not a Keychain
    /// operation. Exactly six keys pin generic-password/service/account matching,
    /// one Data result and a context prohibiting interaction; no authentication is performed.
    @Test("Security query is exact, data-only, one-match, and no-UI")
    func nativeQueryPolicy() {
        let query = NativeKeychainLookup.Query(service: " service \n", account: " account \t")
        let attributes = NativeKeychainLookup.securityQuery(for: query)
        #expect(attributes.count == 6)
        #expect(attributes[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(attributes[kSecAttrService as String] as? String == query.service)
        #expect(attributes[kSecAttrAccount as String] as? String == query.account)
        #expect(attributes[kSecMatchLimit as String] as? String == kSecMatchLimitOne as String)
        #expect(attributes[kSecReturnData as String] as? Bool == true)
        #expect((attributes[kSecUseAuthenticationContext as String] as? LAContext)?.interactionNotAllowed == true)
    }

    /// Pins portable pure-status fixtures against the SDK constants without
    /// calling SecItemCopyMatching, SecItemAdd, or any other Keychain function.
    @Test("portable status values match the macOS SDK")
    func statusConstantParity() {
        #expect(NativeKeychainLookup.Status.success.rawValue == errSecSuccess)
        #expect(NativeKeychainLookup.Status.itemNotFound.rawValue == errSecItemNotFound)
        #expect(NativeKeychainLookup.Status.interactionNotAllowed.rawValue == errSecInteractionNotAllowed)
        #expect(NativeKeychainLookup.Status.interactionRequired.rawValue == errSecInteractionRequired)
        #expect(NativeKeychainLookup.Status.authFailed.rawValue == errSecAuthFailed)
        #expect(NativeKeychainLookup.Status.noAccessForItem.rawValue == errSecNoAccessForItem)
        #expect(NativeKeychainLookup.Status.userCanceled.rawValue == errSecUserCanceled)
        #expect(NativeKeychainLookup.Status.missingEntitlement.rawValue == errSecMissingEntitlement)
        #expect(NativeKeychainLookup.Status.notAvailable.rawValue == errSecNotAvailable)
        #expect(NativeKeychainLookup.Status.decode.rawValue == errSecDecode)
        #expect(NativeKeychainLookup.Status.parameter.rawValue == errSecParam)
    }
    #else
    /// The conditional live branch can be tested only off macOS, where it is a
    /// fixed fail-closed throw and cannot invoke a real system Keychain API.
    @Test("nonmac live provider fails closed")
    func unsupportedPlatform() async {
        let executor = BoundedSecretLookup()
        let provider = MacOSKeychainSecretProvider(runner: .live, executor: executor)
        await assertProviderFailure(provider, expected: .backendUnavailable("native keychain lookup requires macOS Security framework"))
        await executor.drainForTesting()
    }
    #endif

    /// The preserved Runner(lookup:) shape still propagates the exact existing
    /// notFound error, satisfying the broker's current injected keychain test.
    /// A private lane avoids interference with other parallel test suites.
    @Test("legacy runner initializer and notFound mapping are preserved")
    func runnerCompatibility() async {
        let executor = BoundedSecretLookup()
        let expected = SecretProviderError.notFound(service: "svc", account: "acct")
        let runner = MacOSKeychainSecretProvider.Runner(lookup: { _, _ in throw expected })
        let provider = MacOSKeychainSecretProvider(runner: runner, executor: executor)
        await assertProviderFailure(provider, expected: expected)
        await executor.drainForTesting()
    }

    /// Tests the async provider's effect shell plus native pure adapter together,
    /// while its synchronous injected effect remains entirely synthetic.
    @Test("native adapter errors flow through the bounded provider")
    func adapterThroughProvider() async {
        let executor = BoundedSecretLookup()
        let adapter = NativeKeychainLookup.Adapter { _ in
            .init(status: NativeKeychainLookup.Status.interactionNotAllowed.rawValue, payload: .data(Data(Self.canary.utf8)))
        }
        let runner = MacOSKeychainSecretProvider.Runner { service, account in
            try NativeKeychainLookup.lookup(service: service, account: account, adapter: adapter)
        }
        await assertProviderFailure(
            .init(runner: runner, executor: executor),
            expected: .backendUnavailable("keychain locked or interaction required; UI disabled")
        )
        await executor.drainForTesting()
    }

    /// Caller is main-actor isolated; the injected lookup records that it ran
    /// off-main. This supplements code inspection of workerQueue.async; being
    /// off-main alone is not claimed as proof of cooperative-executor exclusion.
    @Test("runner executes off-main and returns injected bytes unchanged")
    @MainActor
    func offMainAndInjectedValueCompatibility() async throws {
        let executor = BoundedSecretLookup()
        let recorder = CallRecorder()
        let runner = MacOSKeychainSecretProvider.Runner { _, _ in
            recorder.record()
            return "\n injected-value \r\n"
        }
        let value = try await MacOSKeychainSecretProvider(runner: runner, executor: executor).secret(for: Self.reference)
        await executor.drainForTesting()
        #expect(value == "\n injected-value \r\n")
        #expect(recorder.callCount == 1)
        #expect(recorder.sawMainThread == false)
    }

    /// Injected and in-memory providers historically accepted empty values; only
    /// the live native success-data path gains the found-but-unusable check.
    @Test("injected and in-memory empty strings remain compatible")
    func injectedEmptyString() async throws {
        let executor = BoundedSecretLookup()
        let provider = MacOSKeychainSecretProvider(runner: .init { _, _ in "" }, executor: executor)
        #expect(try await provider.secret(for: Self.reference) == "")
        #expect(try await InMemorySecretProvider(values: [Self.reference: ""]).secret(for: Self.reference) == "")
        await executor.drainForTesting()
    }

    /// Cancellation of AsyncStream.next is cooperative. The test cancels before
    /// allowing the provider call, so admission/runner invocation must never occur.
    @Test("pre-canceled caller does not invoke a runner")
    func cancellationBeforeAdmission() async {
        let executor = BoundedSecretLookup()
        let recorder = CallRecorder()
        let (start, signal) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let provider = MacOSKeychainSecretProvider(runner: .init { _, _ in recorder.record(); return Self.canary }, executor: executor)
        let task = Task {
            var iterator = start.makeAsyncIterator()
            _ = await iterator.next()
            return try await provider.secret(for: Self.reference)
        }
        task.cancel()
        signal.finish()
        assertCanceled(await task.result)
        await executor.drainForTesting()
        #expect(recorder.callCount == 0)
        #expect(executor.snapshot == .idle)
    }

    /// The synchronous fixture blocks ONLY the dispatch worker. Canceling its
    /// async caller must return CancellationError before releasing the fixture;
    /// another provider sharing the same lane must still fail busy. Late canary
    /// completion then drains without a double resume or capacity leak.
    @Test("running cancellation abandons waiting but retains native capacity")
    func cancellationDuringLookup() async {
        let executor = BoundedSecretLookup()
        let fixture = BlockingFixture()
        defer { fixture.release() }
        let provider = MacOSKeychainSecretProvider(runner: .init { [fixture] service, account in
            try fixture.lookup(service, account)
        }, executor: executor)
        let task = Task { try await provider.secret(for: Self.reference) }
        guard await confirmEntry(fixture, task: task, executor: executor) else { return }
        task.cancel()
        assertCanceled(await task.result)
        #expect(executor.snapshot == .running)
        let excess = CallRecorder()
        let other = MacOSKeychainSecretProvider(runner: .init { _, _ in excess.record(); return Self.canary }, executor: executor)
        await assertProviderFailure(other, expected: .backendUnavailable("keychain lookup busy"))
        #expect(excess.callCount == 0)
        fixture.release()
        await executor.drainForTesting()
        #expect(executor.snapshot == .idle)
        #expect(fixture.calls.callCount == 1)
    }

    /// One real dispatch deadline is exercised, with no millisecond timing claim.
    /// The fixture has a ten-second independent failsafe; the caller deadline is
    /// one second. No Security call occurs, and capacity remains occupied until
    /// the test explicitly releases the fixture and joins its dispatch barrier.
    @Test("caller deadline does not pretend to time out synchronous native work")
    func deadlineDuringLookup() async {
        let executor = BoundedSecretLookup(waitTimeout: .seconds(1))
        let fixture = BlockingFixture()
        defer { fixture.release() }
        let provider = MacOSKeychainSecretProvider(runner: .init { [fixture] service, account in
            try fixture.lookup(service, account)
        }, executor: executor)
        let task = Task { try await provider.secret(for: Self.reference) }
        guard await confirmEntry(fixture, task: task, executor: executor) else { return }
        assertFailure(await task.result, expected: .backendUnavailable("keychain lookup wait timed out"))
        #expect(executor.snapshot == .running)
        await assertProviderFailure(provider, expected: .backendUnavailable("keychain lookup busy"))
        fixture.release()
        await executor.drainForTesting()
        #expect(executor.snapshot == .idle)
        #expect(fixture.calls.callCount == 1)
    }

    /// Finite fan-out while one fixture holds the slot proves rejected callers
    /// do not execute their runners or enqueue replacement native calls. Both
    /// providers use the same injected lane, avoiding shared production test state.
    @Test("overload fails immediately without queued runner work")
    func boundedAdmission() async {
        let executor = BoundedSecretLookup()
        let fixture = BlockingFixture()
        defer { fixture.release() }
        let blocking = MacOSKeychainSecretProvider(runner: .init { [fixture] service, account in
            try fixture.lookup(service, account)
        }, executor: executor)
        let task = Task { try await blocking.secret(for: Self.reference) }
        guard await confirmEntry(fixture, task: task, executor: executor) else { return }
        let excess = CallRecorder()
        let other = MacOSKeychainSecretProvider(runner: .init { _, _ in excess.record(); return Self.canary }, executor: executor)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<32 {
                group.addTask { await assertProviderFailure(other, expected: .backendUnavailable("keychain lookup busy")) }
            }
        }
        #expect(excess.callCount == 0)
        #expect(fixture.calls.callCount == 1)
        fixture.release()
        switch await task.result {
        case let .success(value): #expect(value == Self.canary)
        case .failure: Issue.record("expected admitted fixture success")
        }
        await executor.drainForTesting()
        #expect(executor.snapshot == .idle)
    }

    /// A zero finite cutoff is already expired before any worker claim. Whether
    /// the timer or worker observes it first, the runner must never execute. This
    /// pins the cutoff check without depending on short sleep/timer accuracy.
    @Test("expired queued work is skipped without invoking a runner")
    func expiredBeforeClaim() async {
        let executor = BoundedSecretLookup(waitTimeout: .nanoseconds(0))
        let recorder = CallRecorder()
        let provider = MacOSKeychainSecretProvider(runner: .init { _, _ in
            recorder.record()
            return Self.canary
        }, executor: executor)
        await assertProviderFailure(provider, expected: .backendUnavailable("keychain lookup wait timed out"))
        await executor.drainForTesting()
        #expect(recorder.callCount == 0)
        #expect(executor.snapshot == .idle)
    }

    /// Sequential public calls must reclaim capacity BEFORE result delivery;
    /// there is no drain or retry between calls to mask an admission race.
    @Test("successful calls reclaim the lane")
    func successfulCleanup() async throws {
        let executor = BoundedSecretLookup()
        let recorder = CallRecorder()
        let provider = MacOSKeychainSecretProvider(runner: .init { _, _ in recorder.record(); return Self.canary }, executor: executor)
        for _ in 0..<3 {
            #expect(try await provider.secret(for: Self.reference) == Self.canary)
            #expect(executor.snapshot == .idle)
        }
        await executor.drainForTesting()
        #expect(recorder.callCount == 3)
    }

    // MARK: - Safe assertions and finite fixtures

    /// Defines the full status oracle exhaustively; expected strings independently
    /// pin the safe reason contract instead of reusing implementation messages.
    private func expectedFailure(for status: NativeKeychainLookup.Status) -> SecretProviderError {
        switch status {
        case .success: .backendUnavailable("unexpected test success path")
        case .itemNotFound: .notFound(service: Self.reference.service, account: Self.reference.account)
        case .interactionNotAllowed, .interactionRequired: .backendUnavailable("keychain locked or interaction required; UI disabled")
        case .authFailed, .noAccessForItem, .userCanceled, .missingEntitlement: .backendUnavailable("keychain access denied")
        case .decode: .backendUnavailable("keychain item is malformed")
        case .notAvailable: .backendUnavailable("keychain is unavailable")
        case .parameter: .backendUnavailable("keychain query rejected")
        }
    }

    /// Checks malformed-success outcomes without printing any returned value.
    private func assertDecodeFailure(_ payload: NativeKeychainLookup.Payload, expected: SecretProviderError) {
        do {
            _ = try NativeKeychainLookup.decode(.init(status: 0, payload: payload), for: .init(service: "svc", account: "acct"))
            Issue.record("expected malformed-data failure")
        } catch let error as SecretProviderError {
            #expect(error == expected)
            #expect(!error.localizedDescription.contains(Self.canary))
        } catch {
            Issue.record("unexpected native error type")
        }
    }

    /// Captures provider errors without printing successful credential values or
    /// arbitrary injected-error descriptions when an assertion unexpectedly fails.
    private func assertProviderFailure(_ provider: MacOSKeychainSecretProvider, expected: SecretProviderError) async {
        do {
            _ = try await provider.secret(for: Self.reference)
            Issue.record("expected provider failure")
        } catch let error as SecretProviderError {
            #expect(error == expected)
            #expect(!error.localizedDescription.contains(Self.canary))
        } catch {
            Issue.record("unexpected provider error type")
        }
    }

    /// Checks a joined caller's cancellation outcome without describing its value.
    private func assertCanceled(_ result: Result<String, any Error>) {
        switch result {
        case .success: Issue.record("expected cancellation")
        case let .failure(error): #expect(error is CancellationError)
        }
    }

    /// Checks a joined caller's safe typed failure without describing result data.
    private func assertFailure(_ result: Result<String, any Error>, expected: SecretProviderError) {
        switch result {
        case .success: Issue.record("expected safe provider failure")
        case let .failure(error): #expect((error as? SecretProviderError) == expected)
        }
    }

    /// Bounds asynchronous fixture-entry waiting. On setup failure, cancels and
    /// joins the caller, releases the synthetic worker, and drains the lane before
    /// returning; no owned test task is intentionally left running.
    private func confirmEntry(
        _ fixture: BlockingFixture, task: Task<String, any Error>, executor: BoundedSecretLookup
    ) async -> Bool {
        if await fixture.waitForEntry() { return true }
        task.cancel()
        fixture.release()
        _ = await task.result
        await executor.drainForTesting()
        Issue.record("synthetic worker did not enter before fixture setup deadline")
        return false
    }

    /// SAFETY: only NSLock-protected scalar counters cross tasks; no secret data
    /// is recorded. A locked reference fixture implements the synchronous seam.
    private final class CallRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private var mainThread = false

        /// Records invocation count and thread classification, never arguments.
        func record() {
            lock.withLock {
                count += 1
                mainThread = mainThread || Thread.isMainThread
            }
        }

        /// Reads a scalar snapshot while preserving the fixture's lock invariant.
        var callCount: Int { lock.withLock { count } }

        /// Reports whether any injected invocation occurred on the main thread.
        var sawMainThread: Bool { lock.withLock { mainThread } }
    }

    /// SAFETY: immutable thread-safe semaphore/stream handles, a locked recorder,
    /// and a single bounded semaphore wait confined to the dispatched runner.
    /// No Swift executor thread calls `wait`; cleanup signals even on test failure.
    private final class BlockingFixture: @unchecked Sendable {
        let calls = CallRecorder()
        private let gate = DispatchSemaphore(value: 0)
        private let entries: AsyncStream<Void>
        private let entrySignal: AsyncStream<Void>.Continuation

        private enum FixtureError: Error { case gateFailsafe }

        /// Creates a single-entry cooperative notification, not a background task.
        init() {
            let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
            self.entries = stream
            self.entrySignal = continuation
        }

        /// Synchronous synthetic effect: parks only the dispatch worker and exits
        /// after an explicit release or a finite ten-second fixture failsafe.
        func lookup(_ service: String, _ account: String) throws -> String {
            calls.record()
            entrySignal.yield(())
            defer { entrySignal.finish() }
            guard gate.wait(timeout: .now() + .seconds(10)) == .success else { throw FixtureError.gateFailsafe }
            return NativeKeychainLookupTests.canary
        }

        /// This timeout race is safe because AsyncStream.next and Task.sleep are
        /// both cancelable; no task-group child invokes synchronous Security/I/O.
        func waitForEntry() async -> Bool {
            await withTaskGroup(of: Bool.self) { group in
                group.addTask { [entries] in
                    var iterator = entries.makeAsyncIterator()
                    guard let _ = await iterator.next() else { return false }
                    return true
                }
                group.addTask {
                    do { try await Task.sleep(for: .seconds(2)) } catch { return false }
                    return false
                }
                let entered = await group.next() ?? false
                group.cancelAll()
                return entered
            }
        }

        /// Releases the synthetic worker; repeat signals during cleanup are safe.
        func release() { gate.signal() }
    }
}
