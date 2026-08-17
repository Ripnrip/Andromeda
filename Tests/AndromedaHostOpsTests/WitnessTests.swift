import AndromedaHostOps
import AndromedaSecrets
import Foundation
import Testing

// MARK: - Test helpers

/// Fixed-date provider for deterministic tests.
private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
private let dateProvider: @Sendable () -> Date = { fixedDate }

/// Creates a standard test configuration with one target.
private func makeConfiguration(
    owner: String = "test-owner",
    host: String = "test-host",
    failureThreshold: Int = 3,
    targets: [WitnessTarget] = [
        WitnessTarget(label: "test-target", url: "http://localhost:8788/health", timeoutSeconds: 2),
    ],
    stateDirectory: String = "/tmp/andromeda-witness-test",
    telegram: TelegramConfig? = nil
) -> WitnessConfiguration {
    WitnessConfiguration(
        owner: owner,
        host: host,
        targets: targets,
        failureThreshold: failureThreshold,
        stateDirectory: stateDirectory,
        telegram: telegram
    )
}

/// Creates a probe result with the given outcome.
private func makeProbeResult(
    label: String = "test-target",
    outcome: WitnessProbeResult.Outcome
) -> WitnessProbeResult {
    WitnessProbeResult(
        targetLabel: label,
        outcome: outcome,
        checkedAt: fixedDate
    )
}

// MARK: - Consecutive failure gate tests

@Suite("WitnessEngine consecutive failure gate")
struct WitnessConsecutiveGateTests {
    /// unknown → failed must only happen after `failureThreshold` consecutive failures.
    @Test("unknown to failed requires threshold consecutive failures")
    func unknownToFailedRequiresThreshold() async throws {
        let store = InMemoryWitnessStore()
        let notifier = RecordingWitnessNotifier()
        let probe = RecordedWitnessProbe(results: [
            makeProbeResult(outcome: .connectionFailure("refused")),
            makeProbeResult(outcome: .connectionFailure("refused")),
            makeProbeResult(outcome: .connectionFailure("refused")),
        ])
        let config = makeConfiguration(failureThreshold: 3)
        let engine = WitnessEngine(
            probe: probe,
            store: store,
            notifier: notifier,
            dateProvider: dateProvider
        )

        let target = config.targets[0]

        // First failure: below threshold, stay unknown
        let r1 = try await engine.check(target: target, configuration: config)
        #expect(r1.currentStatus == .unknown)
        #expect(r1.transition == nil)
        #expect(!r1.notified)

        // Second failure: still below threshold
        let r2 = try await engine.check(target: target, configuration: config)
        #expect(r2.currentStatus == .unknown)
        #expect(r2.transition == nil)
        #expect(!r2.notified)

        // Third failure: at threshold → transition to failed
        let r3 = try await engine.check(target: target, configuration: config)
        #expect(r3.currentStatus == .failed)
        #expect(r3.transition != nil)
        #expect(r3.transition?.kind == .alert)
        #expect(r3.notified)
        #expect(r3.consecutiveFailures == 3)
    }

    /// healthy → failed must only happen after `failureThreshold` consecutive failures.
    @Test("healthy to failed requires threshold consecutive failures")
    func healthyToFailedRequiresThreshold() async throws {
        let store = InMemoryWitnessStore()
        let notifier = RecordingWitnessNotifier()
        let probe = RecordedWitnessProbe(results: [
            makeProbeResult(outcome: .success(statusCode: 200)),
            makeProbeResult(outcome: .connectionFailure("refused")),
            makeProbeResult(outcome: .connectionFailure("refused")),
            makeProbeResult(outcome: .connectionFailure("refused")),
        ])
        let config = makeConfiguration(failureThreshold: 3)
        let engine = WitnessEngine(
            probe: probe,
            store: store,
            notifier: notifier,
            dateProvider: dateProvider
        )

        let target = config.targets[0]

        // First: establish healthy
        let r1 = try await engine.check(target: target, configuration: config)
        #expect(r1.currentStatus == .healthy)
        #expect(r1.transition?.kind == .established)
        #expect(!r1.notified) // establishment does not notify

        // First failure: below threshold, stay healthy
        let r2 = try await engine.check(target: target, configuration: config)
        #expect(r2.currentStatus == .healthy)
        #expect(r2.transition == nil)

        // Second failure: still below threshold
        let r3 = try await engine.check(target: target, configuration: config)
        #expect(r3.currentStatus == .healthy)
        #expect(r3.transition == nil)

        // Third failure: at threshold → alert
        let r4 = try await engine.check(target: target, configuration: config)
        #expect(r4.currentStatus == .failed)
        #expect(r4.transition?.kind == .alert)
        #expect(r4.notified)
    }
}

// MARK: - Success reset / recovery tests

@Suite("WitnessEngine success reset and recovery")
struct WitnessRecoveryTests {
    /// A single success after failures resets the consecutive failure counter.
    @Test("single success resets consecutive failure count")
    func successResetsFailureCount() async throws {
        let store = InMemoryWitnessStore()
        let notifier = RecordingWitnessNotifier()
        let probe = RecordedWitnessProbe(results: [
            makeProbeResult(outcome: .connectionFailure("refused")),
            makeProbeResult(outcome: .connectionFailure("refused")),
            makeProbeResult(outcome: .success(statusCode: 200)),
            makeProbeResult(outcome: .connectionFailure("refused")),
        ])
        let config = makeConfiguration(failureThreshold: 3)
        let engine = WitnessEngine(
            probe: probe,
            store: store,
            notifier: notifier,
            dateProvider: dateProvider
        )

        let target = config.targets[0]

        _ = try await engine.check(target: target, configuration: config) // fail 1 (unknown, below threshold)
        _ = try await engine.check(target: target, configuration: config) // fail 2 (unknown, below threshold)
        let r3 = try await engine.check(target: target, configuration: config) // success → unknown→healthy established
        #expect(r3.consecutiveFailures == 0)
        #expect(r3.currentStatus == .healthy) // unknown + success → healthy established
        #expect(r3.transition?.kind == .established)

        // Next failure should start counting from 1, not 3
        let r4 = try await engine.check(target: target, configuration: config)
        #expect(r4.consecutiveFailures == 1)
        #expect(r4.currentStatus == .healthy) // still healthy, below threshold
        #expect(r4.transition == nil)
    }

    /// failed → healthy on a single success: recovery transition + notification.
    @Test("failed to healthy sends recovery notification")
    func failedToHealthyRecovery() async throws {
        let store = InMemoryWitnessStore()
        let notifier = RecordingWitnessNotifier()
        let probe = RecordedWitnessProbe(results: [
            // Establish healthy first
            makeProbeResult(outcome: .success(statusCode: 200)),
            // Three failures to get to failed
            makeProbeResult(outcome: .connectionFailure("refused")),
            makeProbeResult(outcome: .connectionFailure("refused")),
            makeProbeResult(outcome: .connectionFailure("refused")),
            // One success → recovery
            makeProbeResult(outcome: .success(statusCode: 204)),
        ])
        let config = makeConfiguration(failureThreshold: 3)
        let engine = WitnessEngine(
            probe: probe,
            store: store,
            notifier: notifier,
            dateProvider: dateProvider
        )

        let target = config.targets[0]

        _ = try await engine.check(target: target, configuration: config) // established
        _ = try await engine.check(target: target, configuration: config) // fail 1
        _ = try await engine.check(target: target, configuration: config) // fail 2
        let r4 = try await engine.check(target: target, configuration: config) // fail 3 → alert
        #expect(r4.currentStatus == .failed)

        let r5 = try await engine.check(target: target, configuration: config) // success → recovery
        #expect(r5.currentStatus == .healthy)
        #expect(r5.transition?.kind == .recovery)
        #expect(r5.notified)
        #expect(r5.consecutiveFailures == 0)

        let captured = await notifier.captured
        #expect(captured.count == 2) // alert + recovery
        #expect(captured[0].kind == .alert)
        #expect(captured[1].kind == .recovery)
    }
}

// MARK: - Initial healthy no alert test

@Suite("WitnessEngine initial establishment")
struct WitnessEstablishmentTests {
    /// unknown → healthy establishes state without sending a recovery notification.
    @Test("initial unknown to healthy does not send recovery notification")
    func initialHealthyNoAlert() async throws {
        let store = InMemoryWitnessStore()
        let notifier = RecordingWitnessNotifier()
        let probe = RecordedWitnessProbe(results: [
            makeProbeResult(outcome: .success(statusCode: 200)),
        ])
        let config = makeConfiguration()
        let engine = WitnessEngine(
            probe: probe,
            store: store,
            notifier: notifier,
            dateProvider: dateProvider
        )

        let target = config.targets[0]
        let result = try await engine.check(target: target, configuration: config)

        #expect(result.currentStatus == .healthy)
        #expect(result.transition?.kind == .established)
        #expect(!result.notified) // establishment never notifies

        let captured = await notifier.captured
        #expect(captured.isEmpty)
    }
}

// MARK: - No steady-state spam test

@Suite("WitnessEngine steady state")
struct WitnessSteadyStateTests {
    /// Repeated healthy probes must not produce events or notifications.
    @Test("steady healthy state does not spam notifications")
    func noSteadyStateSpam() async throws {
        let store = InMemoryWitnessStore()
        let notifier = RecordingWitnessNotifier()
        let probe = RecordedWitnessProbe(results: [
            makeProbeResult(outcome: .success(statusCode: 200)),
            makeProbeResult(outcome: .success(statusCode: 200)),
            makeProbeResult(outcome: .success(statusCode: 200)),
            makeProbeResult(outcome: .success(statusCode: 200)),
            makeProbeResult(outcome: .success(statusCode: 200)),
        ])
        let config = makeConfiguration()
        let engine = WitnessEngine(
            probe: probe,
            store: store,
            notifier: notifier,
            dateProvider: dateProvider
        )

        let target = config.targets[0]

        let r1 = try await engine.check(target: target, configuration: config)
        #expect(r1.transition?.kind == .established)

        // All subsequent checks: no transitions, no notifications
        for _ in 0..<4 {
            let r = try await engine.check(target: target, configuration: config)
            #expect(r.transition == nil)
            #expect(!r.notified)
        }

        let captured = await notifier.captured
        #expect(captured.isEmpty)
    }

    /// Repeated failed probes (already in failed state) must not produce events.
    @Test("steady failed state does not spam notifications")
    func noSteadyStateFailedSpam() async throws {
        let store = InMemoryWitnessStore()
        let notifier = RecordingWitnessNotifier()
        let probe = RecordedWitnessProbe(results: [
            // Three failures to reach failed state
            makeProbeResult(outcome: .connectionFailure("refused")),
            makeProbeResult(outcome: .connectionFailure("refused")),
            makeProbeResult(outcome: .connectionFailure("refused")),
            // Additional failures — steady state
            makeProbeResult(outcome: .connectionFailure("refused")),
            makeProbeResult(outcome: .connectionFailure("refused")),
        ])
        let config = makeConfiguration(failureThreshold: 3)
        let engine = WitnessEngine(
            probe: probe,
            store: store,
            notifier: notifier,
            dateProvider: dateProvider
        )

        let target = config.targets[0]

        _ = try await engine.check(target: target, configuration: config) // fail 1
        _ = try await engine.check(target: target, configuration: config) // fail 2
        let r3 = try await engine.check(target: target, configuration: config) // fail 3 → alert
        #expect(r3.transition?.kind == .alert)

        // Additional failures: no new transitions
        let r4 = try await engine.check(target: target, configuration: config)
        #expect(r4.transition == nil)
        #expect(!r4.notified)

        let r5 = try await engine.check(target: target, configuration: config)
        #expect(r5.transition == nil)
        #expect(!r5.notified)

        let captured = await notifier.captured
        #expect(captured.count == 1) // only the initial alert
    }
}

// MARK: - HTTP classification tests

@Suite("WitnessProbe HTTP classification")
struct WitnessHTTPClassificationTests {
    /// 2xx responses are classified as success.
    @Test("2xx is success")
    func success2xx() {
        let target = WitnessTarget(label: "t", url: "http://localhost:1/health")
        #expect(target.isSuccessStatus(200))
        #expect(target.isSuccessStatus(204))
        #expect(target.isSuccessStatus(299))
    }

    /// Non-2xx responses are not success.
    @Test("non-2xx is not success")
    func non2xxNotSuccess() {
        let target = WitnessTarget(label: "t", url: "http://localhost:1/health")
        #expect(!target.isSuccessStatus(301))
        #expect(!target.isSuccessStatus(401))
        #expect(!target.isSuccessStatus(404))
        #expect(!target.isSuccessStatus(500))
        #expect(!target.isSuccessStatus(503))
    }

    /// Custom success range works correctly.
    @Test("custom success range")
    func customSuccessRange() {
        let target = WitnessTarget(
            label: "t",
            url: "http://localhost:1/health",
            successStatusMin: 200,
            successStatusMax: 229
        )
        #expect(target.isSuccessStatus(200))
        #expect(target.isSuccessStatus(229))
        #expect(!target.isSuccessStatus(230))
        #expect(!target.isSuccessStatus(404))
    }

    /// Probe result reasons are human-readable and distinguish failure types.
    @Test("probe result reasons are descriptive")
    func probeResultReasons() {
        #expect(makeProbeResult(outcome: .success(statusCode: 200)).reason == "HTTP 200")
        #expect(makeProbeResult(outcome: .httpError(statusCode: 503)).reason == "HTTP 503 (non-success status)")
        #expect(makeProbeResult(outcome: .timeout).reason == "timeout")
        #expect(makeProbeResult(outcome: .connectionFailure("refused")).reason == "connection failure: refused")
    }

    /// isSuccessful correctly distinguishes success from failure outcomes.
    @Test("isSuccessful correctly classifies outcomes")
    func isSuccessfulClassification() {
        #expect(makeProbeResult(outcome: .success(statusCode: 200)).isSuccessful)
        #expect(!makeProbeResult(outcome: .httpError(statusCode: 404)).isSuccessful)
        #expect(!makeProbeResult(outcome: .timeout).isSuccessful)
        #expect(!makeProbeResult(outcome: .connectionFailure("refused")).isSuccessful)
    }
}

// MARK: - Store round-trip / atomic state tests

@Suite("WitnessFileStore state persistence")
struct WitnessStoreRoundTripTests {
    /// State round-trips through JSON encoding/decoding.
    @Test("state round trips through JSON")
    func stateRoundTrip() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("witness-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = WitnessFileStore()
        let path = tempDir.appendingPathComponent("test.state.json").path

        var state = WitnessTargetState.initial(targetLabel: "test-target")
        state.status = .healthy
        state.consecutiveFailures = 2
        state.totalChecks = 10
        state.totalFailures = 3
        state.totalRecoveries = 1
        state.lastCheckedAt = fixedDate
        state.lastTransitionAt = fixedDate
        state.lastReason = "HTTP 200"

        try await store.saveState(state, path: path)
        let loaded = try await store.loadState(targetLabel: "test-target", path: path)

        #expect(loaded == state)
    }

    /// Missing state file yields fresh initial state.
    @Test("missing state file yields initial state")
    func missingStateYieldsInitial() async throws {
        let store = WitnessFileStore()
        let path = "/tmp/nonexistent-witness-\(UUID().uuidString).state.json"

        let state = try await store.loadState(targetLabel: "test", path: path)
        #expect(state.status == .unknown)
        #expect(state.consecutiveFailures == 0)
        #expect(state.totalChecks == 0)
    }

    /// Corrupt state file throws an error — does not silently reset.
    @Test("corrupt state file throws error")
    func corruptStateThrows() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("witness-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = WitnessFileStore()
        let path = tempDir.appendingPathComponent("corrupt.state.json").path
        try "{not valid json".write(toFile: path, atomically: true, encoding: .utf8)

        await #expect(throws: WitnessStoreError.self) {
            _ = try await store.loadState(targetLabel: "test", path: path)
        }
    }

    /// Label mismatch throws an error.
    @Test("state label mismatch throws error")
    func labelMismatchThrows() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("witness-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = WitnessFileStore()
        let path = tempDir.appendingPathComponent("mismatch.state.json").path

        let state = WitnessTargetState.initial(targetLabel: "correct-label")
        try await store.saveState(state, path: path)

        await #expect(throws: WitnessStoreError.self) {
            _ = try await store.loadState(targetLabel: "wrong-label", path: path)
        }
    }
}

// MARK: - JSONL transition log tests

@Suite("WitnessFileStore JSONL log")
struct WitnessJSONLTests {
    /// Transition events are appended to the JSONL log and can be read back.
    @Test("transitions are appended and read back")
    func transitionsAppendedAndRead() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("witness-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = WitnessFileStore()
        let path = tempDir.appendingPathComponent("test.transitions.jsonl").path

        let event1 = WitnessTransitionEvent(
            kind: .established,
            targetLabel: "target-a",
            owner: "owner",
            host: "host",
            fromStatus: .unknown,
            toStatus: .healthy,
            reason: "HTTP 200",
            timestamp: fixedDate,
            consecutiveFailures: 0
        )
        let event2 = WitnessTransitionEvent(
            kind: .alert,
            targetLabel: "target-a",
            owner: "owner",
            host: "host",
            fromStatus: .healthy,
            toStatus: .failed,
            reason: "timeout",
            timestamp: fixedDate.addingTimeInterval(60),
            consecutiveFailures: 3
        )

        try await store.appendTransition(event1, path: path)
        try await store.appendTransition(event2, path: path)

        let events = try await store.readTransitions(path: path, limit: 10)
        #expect(events.count == 2)
        #expect(events[0] == event1)
        #expect(events[1] == event2)
    }

    /// Reading a non-existent log file returns empty.
    @Test("missing log file returns empty")
    func missingLogReturnsEmpty() async throws {
        let store = WitnessFileStore()
        let events = try await store.readTransitions(
            path: "/tmp/nonexistent-\(UUID().uuidString).jsonl",
            limit: 10
        )
        #expect(events.isEmpty)
    }

    /// Limit caps the number of returned events.
    @Test("limit caps returned events")
    func limitCapsEvents() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("witness-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = WitnessFileStore()
        let path = tempDir.appendingPathComponent("capped.transitions.jsonl").path

        for i in 0..<10 {
            let event = WitnessTransitionEvent(
                kind: .alert,
                targetLabel: "target",
                owner: "owner",
                host: "host",
                fromStatus: .healthy,
                toStatus: .failed,
                reason: "fail \(i)",
                timestamp: fixedDate.addingTimeInterval(TimeInterval(i)),
                consecutiveFailures: i
            )
            try await store.appendTransition(event, path: path)
        }

        let events = try await store.readTransitions(path: path, limit: 3)
        #expect(events.count == 3)
        // Should be the last 3
        #expect(events[0].reason == "fail 7")
        #expect(events[2].reason == "fail 9")
    }
}

// MARK: - Notification capture tests

@Suite("Witness notification capture")
struct WitnessNotificationCaptureTests {
    /// Recording notifier captures events.
    @Test("recording notifier captures events")
    func recordingNotifierCaptures() async {
        let notifier = RecordingWitnessNotifier()
        let event = WitnessTransitionEvent(
            kind: .alert,
            targetLabel: "target",
            owner: "owner",
            host: "host",
            fromStatus: .healthy,
            toStatus: .failed,
            reason: "timeout",
            timestamp: fixedDate,
            consecutiveFailures: 3
        )
        let result = await notifier.notify(event: event)
        #expect(result)
        let captured = await notifier.captured
        #expect(captured.count == 1)
        #expect(captured[0] == event)
    }

    /// No-op notifier reports that no delivery occurred.
    @Test("no-op notifier returns false")
    func noOpNotifierReturns() async {
        let notifier = NoOpWitnessNotifier()
        let event = WitnessTransitionEvent(
            kind: .established,
            targetLabel: "target",
            owner: "owner",
            host: "host",
            fromStatus: .unknown,
            toStatus: .healthy,
            reason: "HTTP 200",
            timestamp: fixedDate,
            consecutiveFailures: 0
        )
        let result = await notifier.notify(event: event)
        #expect(!result)
    }

    /// Failed notification delivery remains durable and retries on a later
    /// steady-state check instead of disappearing with the transition.
    @Test("failed notification retries from durable outbox")
    func failedNotificationRetries() async throws {
        let store = InMemoryWitnessStore()
        let notifier = FlakyWitnessNotifier(results: [false, true])
        let probe = RecordedWitnessProbe(results: [
            makeProbeResult(outcome: .connectionFailure("refused")),
            makeProbeResult(outcome: .connectionFailure("refused")),
        ])
        let config = makeConfiguration(failureThreshold: 1)
        let engine = WitnessEngine(
            probe: probe,
            store: store,
            notifier: notifier,
            dateProvider: dateProvider
        )
        let target = config.targets[0]

        let first = try await engine.check(target: target, configuration: config)
        #expect(first.transition?.kind == .alert)
        #expect(!first.notified)

        let pending = try await store.loadState(
            targetLabel: target.label,
            path: config.stateFilePath(for: target)
        )
        #expect(pending.pendingNotifications.count == 1)

        let second = try await engine.check(target: target, configuration: config)
        #expect(second.transition == nil)

        let delivered = try await store.loadState(
            targetLabel: target.label,
            path: config.stateFilePath(for: target)
        )
        #expect(delivered.pendingNotifications.isEmpty)
        #expect(await notifier.attemptCount == 2)

        let events = try await store.readTransitions(
            path: config.logFilePath(for: target),
            limit: 10
        )
        #expect(events.count == 1)
    }
}

private actor FlakyWitnessNotifier: WitnessNotifying {
    private var results: [Bool]
    private(set) var attemptCount = 0

    init(results: [Bool]) {
        self.results = results
    }

    func notify(event: WitnessTransitionEvent) async -> Bool {
        attemptCount += 1
        return results.isEmpty ? false : results.removeFirst()
    }
}

// MARK: - Config contains no secrets tests

@Suite("WitnessConfiguration secret safety")
struct WitnessConfigSecretTests {
    /// Configuration must not contain raw secret values — only SecretReference.
    @Test("config contains SecretReference not raw token")
    func configContainsReferenceNotToken() throws {
        let ref = SecretReference(service: "andromeda.telegram", account: "bot-token")
        let config = WitnessConfiguration(
            owner: "owner",
            host: "host",
            targets: [],
            telegram: TelegramConfig(
                botTokenReference: ref,
                chatID: "123456"
            )
        )
        let encoded = try JSONEncoder().encode(config)
        let json = String(data: encoded, encoding: .utf8)!

        // Must contain the reference names (non-secret)
        #expect(json.contains("andromeda.telegram"))
        #expect(json.contains("bot-token"))

        // Must NOT contain a raw token value
        #expect(!json.contains("1234567890:ABCdef"))
        #expect(!json.contains("tokenValue"))
        // Must not have a raw botToken field (only botTokenReference)
        #expect(!json.contains("\"botToken\""))
    }

    /// TelegramConfig carries only a SecretReference, never a raw token.
    @Test("telegram config has no raw token field")
    func telegramConfigHasNoRawToken() throws {
        let ref = SecretReference(service: "svc", account: "acct")
        let config = TelegramConfig(botTokenReference: ref, chatID: "chat")
        let encoded = try JSONEncoder().encode(config)
        let json = String(data: encoded, encoding: .utf8)!

        // Only service/account/chatID/apiBaseURL fields — no token value
        #expect(json.contains("service"))
        #expect(json.contains("account"))
        #expect(json.contains("chatID"))
        #expect(!json.contains("\"botToken\""))
        #expect(!json.contains("\"token\""))
    }
}

// MARK: - Telegram token leak prevention tests

@Suite("Witness Telegram token leak prevention")
struct WitnessTelegramLeakTests {
    /// Telegram notifier must not leak the token into persisted state or logs.
    @Test("telegram request does not leak token into persisted state")
    func telegramTokenNotInPersistedState() async throws {
        let fakeToken = "1234567890:ABCdefGHIjklMNOpqrSTUvwxYZ_fake_secret"
        let ref = SecretReference(service: "test-telegram", account: "bot-token")
        let secretProvider = InMemorySecretProvider(values: [ref: fakeToken])

        // Recording HTTP client that captures what it receives
        let capturingClient = CapturingTelegramClient()
        let telegramConfig = TelegramConfig(
            botTokenReference: ref,
            chatID: "test-chat-id",
            apiBaseURL: "https://api.telegram.org"
        )
        let notifier = TelegramWitnessNotifier(
            config: telegramConfig,
            secretProvider: secretProvider,
            httpClient: capturingClient
        )

        let event = WitnessTransitionEvent(
            kind: .alert,
            targetLabel: "target",
            owner: "owner",
            host: "host",
            fromStatus: .healthy,
            toStatus: .failed,
            reason: "timeout",
            timestamp: fixedDate,
            consecutiveFailures: 3
        )

        _ = await notifier.notify(event: event)

        // The token was passed to the HTTP client (for the API call)
        let captured = await capturingClient.lastCall
        #expect(captured?.botToken == fakeToken)

        // But the formatted message (which would be logged/persisted) must NOT contain the token
        let message = TelegramWitnessNotifier.formatMessage(event: event)
        #expect(!message.contains(fakeToken))
        #expect(!message.contains("1234567890"))

        // The transition event itself (persisted in JSONL) must NOT contain the token
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let eventJSON = String(data: try encoder.encode(event), encoding: .utf8)!
        #expect(!eventJSON.contains(fakeToken))
        #expect(!eventJSON.contains("1234567890"))
    }

    /// Telegram notifier returns false when secret resolution fails.
    @Test("telegram notifier returns false on missing secret")
    func telegramNotifierFailsOnMissingSecret() async {
        let ref = SecretReference(service: "nonexistent", account: "token")
        let secretProvider = InMemorySecretProvider(values: [:])
        let notifier = TelegramWitnessNotifier(
            config: TelegramConfig(botTokenReference: ref, chatID: "chat"),
            secretProvider: secretProvider,
            httpClient: CapturingTelegramClient()
        )

        let event = WitnessTransitionEvent(
            kind: .alert,
            targetLabel: "t",
            owner: "o",
            host: "h",
            fromStatus: .healthy,
            toStatus: .failed,
            reason: "fail",
            timestamp: fixedDate,
            consecutiveFailures: 1
        )

        let result = await notifier.notify(event: event)
        #expect(!result)
    }
}

// MARK: - Mock Telegram client

/// Captures the last call made to the Telegram API for test assertions.
private actor CapturingTelegramClient: TelegramHTTPClient {
    struct Call: Sendable {
        let baseURL: String
        let botToken: String
        let chatID: String
        let text: String
    }

    private(set) var lastCall: Call?
    private(set) var allCalls: [Call] = []

    func sendMessage(
        baseURL: String,
        botToken: String,
        chatID: String,
        text: String
    ) async -> Bool {
        let call = Call(baseURL: baseURL, botToken: botToken, chatID: chatID, text: text)
        lastCall = call
        allCalls.append(call)
        return true
    }
}

// MARK: - Status report rendering test

@Suite("WitnessStatusReport rendering")
struct WitnessStatusReportTests {
    /// Status report visibly identifies owner, host, last check, status, counters, reasons.
    @Test("status report contains owner host counters and reasons")
    func statusReportContainsKeyInfo() async throws {
        let store = InMemoryWitnessStore()
        let target = WitnessTarget(label: "studio-runtime", url: "http://studio:8788/health")
        let config = makeConfiguration(
            owner: "mini-operator",
            host: "mini",
            targets: [target]
        )

        // Save some state
        var state = WitnessTargetState.initial(targetLabel: "studio-runtime")
        state.status = .healthy
        state.consecutiveFailures = 0
        state.totalChecks = 42
        state.totalFailures = 3
        state.totalRecoveries = 1
        state.lastCheckedAt = fixedDate
        state.lastReason = "HTTP 200"
        try await store.saveState(state, path: config.stateFilePath(for: target))

        let reader = WitnessStatusReader(store: store, dateProvider: dateProvider)
        let report = try await reader.readStatus(configuration: config)
        let rendered = report.render()

        #expect(rendered.contains("mini-operator"))
        #expect(rendered.contains("mini"))
        #expect(rendered.contains("studio-runtime"))
        #expect(rendered.contains("http://studio:8788/health"))
        #expect(rendered.contains("healthy"))
        #expect(rendered.contains("42"))
        #expect(rendered.contains("HTTP 200"))
    }
}
