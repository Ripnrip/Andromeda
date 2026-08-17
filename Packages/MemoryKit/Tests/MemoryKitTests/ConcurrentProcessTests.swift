// Exhibit 3 regression tests: a child that writes far more than the ~64KB
// pipe buffer must drain while it runs. Under the wait-then-read shape this
// test HANGS — that is the bug it pins (same posture as the canon's
// deadlock reproduction), not a flaky timeout.

import Testing
import Foundation
@testable import MemoryKit

@Suite("ConcurrentProcess — drain before wait (Exhibit 3)")
struct ConcurrentProcessTests {

    @Test("child output far exceeding the pipe buffer drains completely")
    func largeOutputDrains() throws {
        // ~345KB — comfortably past the 64KB pipe buffer.
        let payload = String(repeating: "andromeda-drain-probe\n", count: 15_000)
        let fixture = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("andromeda-drain-\(UUID().uuidString).txt")
        try payload.write(to: fixture, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fixture) }

        let output = try ConcurrentProcess.run(executable: "/bin/cat", arguments: [fixture.path])
        #expect(output.status == 0)
        #expect(output.stdout == Data(payload.utf8))
    }

    @Test("exit status and stderr round-trip")
    func statusAndStderr() throws {
        // Direct executable, no shell (repo law: no shell automation, even
        // in fixtures — review caught the /bin/sh -c version). A missing
        // input makes head exit non-zero with a message on stderr.
        // /bin/false does not exist on this macOS (binutils consolidation).
        let missing = "/nonexistent/andromeda-drain-probe-\(UUID().uuidString)"
        let output = try ConcurrentProcess.run(
            executable: "/usr/bin/head",
            arguments: ["-c", "10", missing]
        )
        #expect(output.status != 0)
        #expect(!output.stderr.isEmpty)
    }
}
