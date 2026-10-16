import Foundation
import Testing
@testable import AndromedaMCPHub

/// In-memory stub for hermetic agent-to-agent proof tests (no MemoryKit).
private actor StubAgentMemory: AgentToAgentMemoryProving {
    private var rows: [(id: UUID, narrative: String, agent: String)] = []
    var retainShouldThrow = false
    var retainThrowsCancellation = false
    var cancelDuringRecall = false
    var forceMiss = false

    func retain(narrative: String, project: String, writerAgent: String) async throws -> UUID {
        _ = project
        if retainThrowsCancellation {
            throw CancellationError()
        }
        if retainShouldThrow {
            throw StubError.retainBoom
        }
        let id = UUID()
        rows.append((id, narrative, writerAgent))
        return id
    }

    func recallContains(query: String, memoryID: UUID, readerAgent: String) async -> Bool {
        _ = readerAgent
        if cancelDuringRecall {
            // Cancel the calling task mid-leg (PR #91 P2-3: cancel raced the
            // leg — state must not be mutated afterwards).
            withUnsafeCurrentTask { $0?.cancel() }
        }
        if forceMiss { return false }
        return rows.contains { row in
            row.id == memoryID && row.narrative.localizedCaseInsensitiveContains(query)
        }
    }

    func retainCount() -> Int { rows.count }

    enum StubError: Error, LocalizedError {
        case retainBoom
        var errorDescription: String? { "stub retain boom" }
    }
}

@Suite("MemoryChainProofRunner")
struct MemoryChainProofRunnerTests {
    /// Proof writes must land inside the ADR-0020 sandbox.
    private func sandboxPath(_ name: String) -> String {
        MemoryChainProofStore.sandboxDirectory
            .appendingPathComponent("runner-\(name)-\(UUID().uuidString).json").path
    }

    private func ensureSandbox() throws {
        try FileManager.default.createDirectory(
            at: MemoryChainProofStore.sandboxDirectory,
            withIntermediateDirectories: true
        )
    }

    @Test("agent-to-agent pass writes leg and preserves prior legs")
    func agentToAgentPassMerges() async throws {
        try ensureSandbox()
        let path = sandboxPath("pass")
        defer { try? FileManager.default.removeItem(atPath: path) }

        // Prior Letta leg from HAB-602 Studio proof — must survive merge.
        try MemoryChainProofStore.save(
            MemoryChainProofState(
                lastRun: Date(timeIntervalSince1970: 1),
                legs: [
                    MemoryChainProofLeg(
                        id: MemoryChainProofLegID.lettaIngress.rawValue,
                        status: .pass,
                        at: Date(timeIntervalSince1970: 1),
                        detail: "prior letta-ingress"
                    )
                ]
            ),
            to: path
        )

        let stub = StubAgentMemory()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let state = try await MemoryChainProofRunner.runAgentToAgent(
            surface: stub,
            path: path,
            now: now,
            nonce: "fixed-nonce"
        )

        #expect(state.legs.count == 2)
        let agentLeg = state.legs.first { $0.id == MemoryChainProofLegID.agentToAgent.rawValue }
        let lettaLeg = state.legs.first { $0.id == MemoryChainProofLegID.lettaIngress.rawValue }
        #expect(agentLeg?.status == .pass)
        #expect(agentLeg?.detail.contains("fixed-nonce") == true)
        #expect(lettaLeg?.status == .pass)
        #expect(lettaLeg?.detail == "prior letta-ingress")
        #expect(state.lastRun == now)

        let reloaded = try MemoryChainProofStore.load(from: path)
        #expect(reloaded?.legs.count == 2)
    }

    @Test("agent-to-agent miss records fail not pending")
    func agentToAgentMissFails() async throws {
        try ensureSandbox()
        let path = sandboxPath("miss")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let stub = StubAgentMemory()
        await stub.setForceMiss(true)
        let state = try await MemoryChainProofRunner.runAgentToAgent(
            surface: stub,
            path: path,
            nonce: "miss-nonce"
        )
        #expect(state.legs.first?.status == .fail)
        #expect(state.legs.first?.detail.contains("missed") == true)
    }

    @Test("retain errors record fail")
    func retainErrorFails() async throws {
        try ensureSandbox()
        let path = sandboxPath("err")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let stub = StubAgentMemory()
        await stub.setRetainShouldThrow(true)
        let state = try await MemoryChainProofRunner.runAgentToAgent(surface: stub, path: path)
        #expect(state.legs.first?.status == .fail)
        #expect(state.legs.first?.detail.contains("retain failed") == true)
    }

    @Test("ladybug probe merges ladybug-index leg")
    func ladybugLegMerges() async throws {
        try ensureSandbox()
        let path = sandboxPath("ladybug")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let now = Date(timeIntervalSince1970: 42)
        let probe = FixedLadybugProbe(
            leg: MemoryChainProofLeg(
                id: MemoryChainProofLegID.ladybugIndex.rawValue,
                status: .pending,
                at: now,
                detail: "health ok; upsert pending"
            )
        )
        let state = try await MemoryChainProofRunner.runLadybugIndex(probe: probe, path: path, now: now)
        #expect(state.legs.count == 1)
        #expect(state.legs[0].id == MemoryChainProofLegID.ladybugIndex.rawValue)
        #expect(state.legs[0].status == .pending)
    }

    @Test("unreachable ladybug health is honest pending")
    func ladybugUnreachablePending() async throws {
        try ensureSandbox()
        let path = sandboxPath("ladybug-down")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let probe = LadybugHTTPHealthProbe(
            baseURL: URL(string: "http://127.0.0.1:8286")!,
            http: FixedHTTPStatusProbe(error: URLError(.cannotConnectToHost))
        )
        let state = try await MemoryChainProofRunner.runLadybugIndex(probe: probe, path: path)
        let leg = state.legs.first { $0.id == MemoryChainProofLegID.ladybugIndex.rawValue }
        #expect(leg?.status == .pending)
        #expect(leg?.detail.contains("unreachable") == true)
    }

    @Test("ladybug health 200 stays pending until upsert/query proven")
    func ladybugHealthyStillPending() async throws {
        try ensureSandbox()
        let path = sandboxPath("ladybug-200")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let probe = LadybugHTTPHealthProbe(
            http: FixedHTTPStatusProbe(code: 200)
        )
        let state = try await MemoryChainProofRunner.runLadybugIndex(probe: probe, path: path)
        let leg = state.legs.first { $0.id == MemoryChainProofLegID.ladybugIndex.rawValue }
        #expect(leg?.status == .pending)
        #expect(leg?.detail.contains("upsert/query") == true)
    }

    // MARK: PR #91 review — P1-1 (transaction + atomic publish)

    /// Regression (PR #91 P1-1): two legs merged concurrently against the same
    /// document must BOTH survive. Before the cross-process lock, the unlocked
    /// read-merge-write let whichever save landed second clobber the first leg.
    @Test("concurrent two-leg merges both survive the transaction lock")
    func concurrentMergesDoNotLoseLegs() async throws {
        try ensureSandbox()
        // Run several rounds: a single race window can pass by luck.
        for round in 0..<5 {
            let path = sandboxPath("concurrent-\(round)")
            defer { try? FileManager.default.removeItem(atPath: path) }
            defer { try? FileManager.default.removeItem(atPath: path + ".lock") }

            let agentLeg = MemoryChainProofLeg(
                id: MemoryChainProofLegID.agentToAgent.rawValue,
                status: .pass,
                at: Date(timeIntervalSince1970: 100),
                detail: "agent leg \(round)"
            )
            let ladybugLeg = MemoryChainProofLeg(
                id: MemoryChainProofLegID.ladybugIndex.rawValue,
                status: .pending,
                at: Date(timeIntervalSince1970: 100),
                detail: "ladybug leg \(round)"
            )

            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    _ = try MemoryChainProofRunner.mergeAndSave(leg: agentLeg, path: path)
                }
                group.addTask {
                    _ = try MemoryChainProofRunner.mergeAndSave(leg: ladybugLeg, path: path)
                }
                try await group.waitForAll()
            }

            let merged = try MemoryChainProofStore.load(from: path)
            #expect(merged?.legs.count == 2, "round \(round): both legs must survive the merge")
            #expect(
                merged?.legs.map(\.id).sorted()
                    == [MemoryChainProofLegID.agentToAgent.rawValue,
                        MemoryChainProofLegID.ladybugIndex.rawValue].sorted(),
                "round \(round): expected agent-to-agent + ladybug-index"
            )
        }
    }

    // MARK: PR #91 review — P2-3 (cancellation + idempotency)

    /// Cancellation during retain propagates: no fail leg, no document write —
    /// cancellation is not a proof result.
    @Test("cancelled retain propagates without recording a leg")
    func cancelledRetainPropagates() async throws {
        try ensureSandbox()
        let path = sandboxPath("cancel-retain")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let stub = StubAgentMemory()
        await stub.setRetainThrowsCancellation(true)

        await #expect(throws: CancellationError.self) {
            _ = try await MemoryChainProofRunner.runAgentToAgent(surface: stub, path: path)
        }
        #expect(try MemoryChainProofStore.load(from: path) == nil)
    }

    /// Cancellation that races the leg (after retain, before merge) must not
    /// mutate state afterwards: the run throws and the document stays absent.
    @Test("cancel racing the leg leaves the proof document untouched")
    func cancelAfterRecallDoesNotMutateState() async throws {
        try ensureSandbox()
        let path = sandboxPath("cancel-recall")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let stub = StubAgentMemory()
        await stub.setCancelDuringRecall(true)

        // Run the leg in a child task so the stub's self-cancellation targets
        // the runner, not this test task.
        let thrown: (any Error)?
        do {
            _ = try await Task.detached(priority: .userInitiated) {
                try await MemoryChainProofRunner.runAgentToAgent(surface: stub, path: path)
            }.value
            thrown = nil
        } catch {
            thrown = error
        }
        #expect(thrown is CancellationError)
        #expect(try MemoryChainProofStore.load(from: path) == nil)
    }

    /// A keyed run that already passed short-circuits: no second durable
    /// retain, prior state returned verbatim (PR #91 P2-3 idempotency).
    @Test("same run key after a pass does not retain again")
    func runKeyReplayIsIdempotent() async throws {
        try ensureSandbox()
        let path = sandboxPath("runkey")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let first = StubAgentMemory()
        let passed = try await MemoryChainProofRunner.runAgentToAgent(
            surface: first, path: path, nonce: "rk-token", runKey: "rk-91"
        )
        #expect(passed.legs.first?.status == .pass)
        #expect(passed.legs.first?.runKey == "rk-91")
        #expect(await first.retainCount() == 1)

        // Retry with a fresh surface and the same key: no new durable retain.
        let retry = StubAgentMemory()
        let replayed = try await MemoryChainProofRunner.runAgentToAgent(
            surface: retry, path: path, runKey: "rk-91"
        )
        #expect(await retry.retainCount() == 0, "keyed replay must not retain again")
        #expect(replayed.legs.first?.status == .pass)
        #expect(replayed.legs.first?.runKey == "rk-91")
        // Verbatim = byte-identical to what is on disk (disk-to-disk compare
        // avoids ISO-8601 sub-second truncation tripping Date equality).
        let onDisk = try MemoryChainProofStore.load(from: path)
        #expect(replayed == onDisk)
    }

    /// A keyed run that FAILED replays (a fail is attempted, not proven) —
    /// retries after failure are allowed and re-attempt the retain.
    @Test("same run key after a fail re-attempts the leg")
    func runKeyFailureReplays() async throws {
        try ensureSandbox()
        let path = sandboxPath("runkey-fail")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let stub = StubAgentMemory()
        await stub.setForceMiss(true)
        let failed = try await MemoryChainProofRunner.runAgentToAgent(
            surface: stub, path: path, runKey: "rk-fail"
        )
        #expect(failed.legs.first?.status == .fail)

        await stub.setForceMiss(false)
        let retried = try await MemoryChainProofRunner.runAgentToAgent(
            surface: stub, path: path, runKey: "rk-fail"
        )
        #expect(retried.legs.first?.status == .pass)
        #expect(await stub.retainCount() == 2)
    }

    // MARK: PR #91 review — P2-2 (reader authorization policy)

    /// Typed allow/deny matrix: the shared proof policy allows cross-agent
    /// reads; writerOnly denies everyone but the writer.
    @Test("read policy authorizes readers by design, not by omission")
    func readPolicyMatrix() {
        let shared = AgentMemoryReadPolicy.sharedAcrossAgents
        #expect(shared.retentionVisibility == "shared")
        #expect(shared.authorizes(reader: "agent-b", writer: "agent-a") == true)
        #expect(shared.authorizes(reader: "agent-a", writer: "agent-a") == true)

        let writerOnly = AgentMemoryReadPolicy.writerOnly
        #expect(writerOnly.retentionVisibility == "private")
        #expect(writerOnly.authorizes(reader: "agent-b", writer: "agent-a") == false)
        #expect(writerOnly.authorizes(reader: "agent-a", writer: "agent-a") == true)
    }
}

extension StubAgentMemory {
    func setForceMiss(_ value: Bool) { forceMiss = value }
    func setRetainShouldThrow(_ value: Bool) { retainShouldThrow = value }
    func setRetainThrowsCancellation(_ value: Bool) { retainThrowsCancellation = value }
    func setCancelDuringRecall(_ value: Bool) { cancelDuringRecall = value }
}
