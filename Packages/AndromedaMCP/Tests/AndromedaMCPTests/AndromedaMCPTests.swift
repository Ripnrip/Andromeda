// End-to-end protocol test: drives the built server binary over stdio and
// asserts a real code.search / code.replace round-trip.

import Foundation
import Testing

@Suite("MCP protocol")
struct AndromedaMCPTests {

    /// Locate the binary SwiftPM built (debug or release) relative to this file.
    private static var serverBinary: URL {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // AndromedaMCPTests.swift
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // package root
        let release = packageRoot.appendingPathComponent(".build/release/andromeda-mcp")
        let debug = packageRoot.appendingPathComponent(".build/debug/andromeda-mcp")
        return FileManager.default.fileExists(atPath: release.path) ? release : debug
    }

    /// One response line, decoded: result.content[0].text or the raw error text.
    private func textPayload(of line: String) throws -> String {
        let json = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        if let error = json?["error"] as? [String: Any] {
            return "error: \(error["message"] ?? "?")"
        }
        let result = json?["result"] as? [String: Any]
        let content = result?["content"] as? [[String: Any]]
        return (content?.first)?["text"] as? String ?? ""
    }

    /// Run a scripted line-delimited JSON-RPC exchange against the server.
    /// Each call gets its own uniquely-named fixture directory — tests run
    /// in parallel and must not share (or delete) each other's cwd.
    /// `setup` runs after the fixture directory is created, for extra files
    /// or symlinks a test wants inside the workspace root.
    private func runExchange(
        _ requests: [String],
        fixtureName: String,
        expectedResponses: Int? = nil,
        setup: ((URL) throws -> Void)? = nil
    ) throws -> [String] {
        // Tests that deliberately provoke silence get fewer responses than
        // requests — waiting for requests.count would block on a read with
        // no EOF guarantee while the child still holds the pipe.
        let expected = expectedResponses ?? requests.count
        let fixtureDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("andromeda-mcp-\(fixtureName)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
        let fixture = fixtureDirectory.appendingPathComponent("fixture.swift")
        try """
        func demo() {
            print("one")
            print("two")
        }
        """.write(to: fixture, atomically: true, encoding: .utf8)
        try setup?(fixtureDirectory)

        let process = Process()
        process.executableURL = Self.serverBinary
        process.currentDirectoryURL = fixtureDirectory
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = Pipe()

        let script = requests
            .map { $0.replacingOccurrences(of: "__PATH__", with: fixture.path) }
            .joined(separator: "\n") + "\n"

        try process.run()
        stdin.fileHandleForWriting.write(Data(script.utf8))
        stdin.fileHandleForWriting.closeFile()

        var responses: [String] = []
        var buffer = Data()
        while responses.count < expected {
            let chunk = stdout.fileHandleForReading.availableData
            guard !chunk.isEmpty else { break }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = buffer[buffer.startIndex..<newline]
                buffer = Data(buffer[buffer.index(after: newline)...])
                responses.append(String(decoding: line, as: UTF8.self))
                if responses.count == expected { break }
            }
        }
        process.terminate()
        return responses
    }

    @Test("initialize, tools/list, and search round-trip")
    func searchRoundTrip() throws {
        let responses = try runExchange([
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#,
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"code.search","arguments":{"pattern":"print($MSG)","path":"__PATH__"}}}"#,
        ], fixtureName: "search")
        #expect(responses.count == 3, "got \(responses.count): \(responses)")

        #expect(responses[0].contains(#""name":"andromeda-mcp""#))
        #expect(responses[1].contains("code.search"))
        #expect(responses[1].contains("code.replace"))

        let search = try textPayload(of: responses[2])
        #expect(search.contains("Found 2 match(es)"))
        #expect(search.contains(#"print("one")"#))
        #expect(search.contains(#"MSG="one""#))
    }

    @Test("replace dry-run previews without writing")
    func replaceDryRun() throws {
        let responses = try runExchange([
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#,
            #"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"code.replace","arguments":{"pattern":"print($MSG)","replacement":"logger.debug($MSG)","path":"__PATH__","dryRun":true}}}"#,
        ], fixtureName: "dryrun")
        #expect(responses.count == 2)
        let payload = try textPayload(of: responses[1])
        #expect(payload.contains("DRY RUN"))
        #expect(payload.contains("logger.debug"))
    }

    @Test("replace with dryRun=false writes to disk")
    func replaceApplies() throws {
        // Reuse the same exchange flow, but point the request at this test's
        // own fixture file by piggybacking on runExchange's __PATH__ token.
        let responses = try runExchange([
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"code.replace","arguments":{"pattern":"print($MSG)","replacement":"logger.debug($MSG)","path":"__PATH__","dryRun":false}}}"#,
        ], fixtureName: "apply")
        #expect(responses.count == 2)
        let payload = try textPayload(of: responses[1])
        #expect(payload.contains("APPLIED"))
        #expect(payload.contains("logger.debug"))
        #expect(!payload.contains("Error"))

        // The fixture runExchange wrote is the one the server rewrote.
        // Re-locate it via the payload's file path.
        let filePath = payload
            .split(separator: "\n")
            .first { $0.contains(":1:") || $0.contains(":2:") }
            .map { String($0.split(separator: ":").first ?? "") } ?? ""
        let rewritten = try String(contentsOfFile: filePath, encoding: .utf8)
        #expect(rewritten.contains(#"logger.debug("one")"#))
        #expect(rewritten.contains(#"logger.debug("two")"#))
        #expect(!rewritten.contains("print("))
    }

    @Test("paths resolving outside the workspace root are rejected")
    func pathContainment() throws {
        let responses = try runExchange([
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"code.search","arguments":{"pattern":"print($MSG)","path":"../../../../etc/hosts"}}}"#,
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"code.search","arguments":{"pattern":"print($MSG)","path":"/etc/hosts"}}}"#,
            #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"code.replace","arguments":{"pattern":"print($MSG)","replacement":"boom($MSG)","path":"/etc/hosts","dryRun":false}}}"#,
            #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"code.search","arguments":{"pattern":"print($MSG)","path":"fixture.swift"}}}"#,
        ], fixtureName: "containment")
        #expect(responses.count == 5, "got \(responses.count): \(responses)")

        let dotDotEscape = try textPayload(of: responses[1])
        #expect(dotDotEscape.contains("escapes workspace root"))

        let absoluteEscape = try textPayload(of: responses[2])
        #expect(absoluteEscape.contains("escapes workspace root"))

        let writeEscape = try textPayload(of: responses[3])
        #expect(writeEscape.contains("escapes workspace root"))

        // Relative paths inside the root still work.
        let relative = try textPayload(of: responses[4])
        #expect(relative.contains("Found 2 match(es)"))
    }

    @Test("large match sets cannot deadlock on pipe buffers")
    func largeOutputDrains() throws {
        // Regression: a match set far larger than the pipe buffer (~64 KB)
        // must drain while the child runs. 3,000 matches ≈ 1.4 MB of JSON.
        let bigFixture = (0..<3_000)
            .map { #"print("line \#($0)")"# }
            .joined(separator: "\n")

        let responses = try runExchange(
            [
                #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#,
                #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"code.search","arguments":{"pattern":"print($MSG)","path":"big.swift"}}}"#,
            ],
            fixtureName: "drain",
            setup: { directory in
                try bigFixture.write(
                    to: directory.appendingPathComponent("big.swift"),
                    atomically: true,
                    encoding: .utf8
                )
            }
        )
        #expect(responses.count == 2)

        let payload = try textPayload(of: responses[1])
        #expect(payload.contains("Found 3000 match(es)"), "got prefix: \(payload.prefix(120))")
    }

    @Test("malformed tool arguments answer with the request id")
    func malformedArgumentsKeepID() throws {
        let responses = try runExchange([
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#,
            #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"code.search","arguments":{"pattern":123}}}"#,
        ], fixtureName: "malformed")
        #expect(responses.count == 2)
        #expect(responses[1].contains(#""id":7"#), "got: \(responses.count > 1 ? responses[1] : "no response")")
        #expect(responses[1].contains("Invalid request"))
    }

    @Test("ping requests get an empty result with the id echoed")
    func pingResponds() throws {
        let responses = try runExchange([
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#,
            #"{"jsonrpc":"2.0","id":42,"method":"ping"}"#,
        ], fixtureName: "ping")
        #expect(responses.count == 2, "got \(responses.count): \(responses)")
        #expect(responses[1].contains(#""id":42"#))
        #expect(responses[1].contains(#""result":{}"#))
        #expect(!responses[1].contains("error"))
    }

    @Test("notification-form pings (no id) get no reply at all")
    func notificationPingStaysSilent() throws {
        let responses = try runExchange([
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#,
            #"{"jsonrpc":"2.0","method":"ping"}"#,
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            #"{"jsonrpc":"2.0","method":"tools/list"}"#,
        ], fixtureName: "notification-silence", expectedResponses: 1)
        // Only the initialize request (which carries an id) is answered —
        // notifications never produce responses, even for request methods
        // sent in notification form.
        #expect(responses.count == 1, "got \(responses.count): \(responses)")
        #expect(responses[0].contains(#""id":1"#))
    }

    @Test("unparseable lines answer -32700 with an explicit null id")
    func parseErrorCarriesNullID() throws {
        let responses = try runExchange([
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#,
            "this is not json",
        ], fixtureName: "parse-null-id")
        #expect(responses.count == 2, "got \(responses.count): \(responses)")
        #expect(responses[1].contains(#""id":null"#))
        #expect(responses[1].contains("-32700"))
    }

    @Test("symlinks pivoting outside the workspace root are rejected")
    func symlinkContainment() throws {
        let outside = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("andromeda-mcp-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let outsideFile = outside.appendingPathComponent("secret.swift")
        try #"func secret() { print("nope") }"#
            .write(to: outsideFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }

        let responses = try runExchange([
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"code.search","arguments":{"pattern":"print($MSG)","path":"link.swift"}}}"#,
        ], fixtureName: "symlink") { fixtureDirectory in
            try FileManager.default.createSymbolicLink(
                at: fixtureDirectory.appendingPathComponent("link.swift"),
                withDestinationURL: outsideFile
            )
        }
        #expect(responses.count == 2)
        let payload = try textPayload(of: responses[1])
        #expect(payload.contains("escapes workspace root"))
    }
}
