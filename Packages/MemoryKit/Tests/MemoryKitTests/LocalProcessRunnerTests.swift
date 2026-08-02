import Foundation
import Testing
@testable import MemoryKit

@Suite("LocalProcessRunner")
struct LocalProcessRunnerTests {

    @Test("Large stdout does not deadlock (pipe drain before wait)")
    func largeStdoutDoesNotDeadlock() async throws {
        let runner = LocalProcessRunner(timeoutSeconds: 5)
        // ~2 MiB — larger than typical pipe buffer; old wait-then-read hung forever.
        let result = try await runner.run(
            executable: "/usr/bin/python3",
            arguments: ["-c", "import sys; sys.stdout.write('x' * 2_000_000)"],
            workingDirectory: nil
        )
        #expect(result.exitCode == 0)
        #expect(result.stdout.count == 2_000_000)
    }

    @Test("Timeout terminates hung child")
    func timeoutTerminatesHungProcess() async {
        let runner = LocalProcessRunner(timeoutSeconds: 0.25)
        await #expect(throws: LocalProcessRunnerError.self) {
            try await runner.run(
                executable: "/bin/sleep",
                arguments: ["10"],
                workingDirectory: nil
            )
        }
    }
}
