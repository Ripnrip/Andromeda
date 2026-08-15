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
    private func runExchange(_ requests: [String], fixtureName: String) throws -> [String] {
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
        while responses.count < requests.count {
            let chunk = stdout.fileHandleForReading.availableData
            guard !chunk.isEmpty else { break }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = buffer[buffer.startIndex..<newline]
                buffer = Data(buffer[buffer.index(after: newline)...])
                responses.append(String(decoding: line, as: UTF8.self))
                if responses.count == requests.count { break }
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
}
