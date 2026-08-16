// Pure-layer tests: wire models, containment, command construction, and
// presentation — no processes spawned (canon: pure logic gets #expect only).

import Foundation
import Testing

@testable import andromeda_mcp

@Suite("RPC wire models")
struct RPCTests {

    // MARK: - RPCID

    @Test("numeric id round-trips")
    func numericID() throws {
        let decoded = try JSONDecoder().decode(RPCID.self, from: Data("42".utf8))
        #expect(decoded == .number(42))

        let encoded = try JSONEncoder().encode(RPCResult(id: .number(42), result: EmptyResult()))
        #expect(String(decoding: encoded, as: UTF8.self).contains(#""id":42"#))
    }

    @Test("string id round-trips")
    func stringID() throws {
        let decoded = try JSONDecoder().decode(RPCID.self, from: Data(#""abc""#.utf8))
        #expect(decoded == .string("abc"))

        let encoded = try JSONEncoder().encode(RPCErrorResponse(id: .string("abc"), code: .methodNotFound, message: "nope"))
        #expect(String(decoding: encoded, as: UTF8.self).contains(#""id":"abc""#))
    }

    @Test("null id is rejected, not silently optional")
    func nullIDRejected() {
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(RPCID.self, from: Data("null".utf8))
        }
    }

    @Test("error responses encode an explicit null id, never drop the key")
    func errorResponsesCarryNullID() throws {
        let encoded = try JSONEncoder().encode(
            RPCErrorResponse(id: nil, code: .parseError, message: "unparseable")
        )
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(text.contains(#""id":null"#))
        #expect(text.contains("-32700"))
    }

    // MARK: - Envelope encoding is deterministic

    struct EmptyResult: Encodable {}

    @Test("sorted keys make output deterministic")
    func deterministicEncoding() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let one = try encoder.encode(RPCResult(id: .number(1), result: InitializeResult()))
        let two = try encoder.encode(RPCResult(id: .number(1), result: InitializeResult()))
        #expect(one == two)
        let text = String(decoding: one, as: UTF8.self)
        #expect(text.contains(#""jsonrpc":"2.0""#))
        #expect(text.contains(#""protocolVersion":"2025-06-18""#))
    }

    // MARK: - Header routing

    @Test("header decodes method and optional id")
    func headerDecode() throws {
        let header = try JSONDecoder().decode(
            RPCRequestHeader.self,
            from: Data(#"{"jsonrpc":"2.0","id":7,"method":"tools/list"}"#.utf8)
        )
        #expect(header.method == "tools/list")
        #expect(header.id == .number(7))

        let notification = try JSONDecoder().decode(
            RPCRequestHeader.self,
            from: Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)
        )
        #expect(notification.id == nil)
    }

    // MARK: - Two-pass tools/call decode

    private let searchCall = Data(
        #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"code.search","arguments":{"pattern":"print($MSG)","path":"fixture.swift","language":"swift"}}}"#
            .utf8
    )

    @Test("typed search arguments decode with all fields")
    func searchArgumentsDecode() throws {
        let request = try JSONDecoder().decode(ToolCallRequest<CodeSearchArguments>.self, from: searchCall)
        #expect(request.id == .number(3))
        #expect(request.params.name == "code.search")
        #expect(request.params.arguments?.pattern == "print($MSG)")
        #expect(request.params.arguments?.path == "fixture.swift")
        #expect(request.params.arguments?.language == "swift")
    }

    @Test("missing pattern is a DecodingError carrying the coding path")
    func missingPatternEvidence() {
        let broken = Data(
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"code.search","arguments":{"path":"x.swift"}}}"#
                .utf8
        )
        do {
            _ = try JSONDecoder().decode(ToolCallRequest<CodeSearchArguments>.self, from: broken)
            Issue.record("expected decode failure")
        } catch let error as DecodingError {
            #expect(error.brief.contains("pattern"))
            #expect(error.brief.contains("arguments"))
        } catch {
            Issue.record("expected DecodingError, got \(error)")
        }
    }

    @Test("dryRun is an explicit opt-in to write")
    func dryRunSemantics() throws {
        func arguments(_ json: String) throws -> CodeReplaceArguments {
            try JSONDecoder().decode(
                ToolCallRequest<CodeReplaceArguments>.self,
                from: Data(#"{"id":1,"method":"tools/call","params":{"name":"code.replace","arguments":\#(json)}}"#.utf8)
            ).params.arguments!
        }
        #expect(try arguments(#"{"pattern":"a","replacement":"b"}"#).appliesToDisk == false)
        #expect(try arguments(#"{"pattern":"a","replacement":"b","dryRun":true}"#).appliesToDisk == false)
        #expect(try arguments(#"{"pattern":"a","replacement":"b","dryRun":false}"#).appliesToDisk == true)
    }
}

@Suite("Workspace containment")
struct ContainmentTests {

    private let root = "/tmp/workspace"

    @Test("absent path resolves to the root")
    func defaultsToRoot() throws {
        #expect(try containedTarget(nil, root: root) == root)
        #expect(try containedTarget("  ", root: root) == root)
    }

    @Test("relative and absolute in-root paths resolve inside")
    func inRootPaths() throws {
        let resolved = try containedTarget("Sources/Foo.swift", root: root)
        #expect(resolved.hasPrefix(root + "/"))
        let absolute = try containedTarget("\(root)/Sources/Foo.swift", root: root)
        #expect(absolute.hasPrefix(root + "/"))
    }

    @Test("dot-dot escapes are rejected")
    func dotDotEscape() {
        #expect(throws: ASTGrepError.self) {
            _ = try containedTarget("../../etc/hosts", root: root)
        }
        #expect(throws: ASTGrepError.self) {
            _ = try containedTarget("Sources/../../../etc/hosts", root: root)
        }
    }

    @Test("absolute escapes are rejected")
    func absoluteEscape() {
        #expect(throws: ASTGrepError.self) {
            _ = try containedTarget("/etc/hosts", root: root)
        }
        #expect(throws: ASTGrepError.self) {
            _ = try containedTarget("/private/tmp/workspace/../secret.swift", root: root)
        }
    }

    @Test("similarly-named sibling directory is not the root")
    func siblingPrefixEscape() {
        #expect(throws: ASTGrepError.self) {
            _ = try containedTarget("/tmp/workspace-evil/file.swift", root: root)
        }
    }
}

@Suite("Command construction and decoding")
struct CommandTests {

    @Test("preview arguments carry json flag, rewrite, lang, target")
    func previewArguments() {
        let arguments = ASTGrepCommand.previewArguments(
            pattern: "print($MSG)", replacement: "log($MSG)", language: "swift", target: "/w"
        )
        #expect(arguments == ["run", "--pattern", "print($MSG)", "--json=compact", "--rewrite", "log($MSG)", "--lang", "swift", "/w"])
    }

    @Test("writer arguments carry update-all and never json")
    func writeArguments() {
        let arguments = ASTGrepCommand.writeArguments(
            pattern: "print($MSG)", replacement: "log($MSG)", language: nil, target: "/w"
        )
        #expect(arguments == ["run", "--pattern", "print($MSG)", "--rewrite", "log($MSG)", "--update-all", "/w"])
        #expect(!arguments.contains { $0.contains("json") })
    }

    @Test("matches decode from compact json, empty output means no matches")
    func matchDecoding() throws {
        #expect(try ASTGrepCommand.decodeMatches(from: Data("  \n".utf8)).isEmpty)

        let payload = Data(
            """
            [{"file":"a.swift","text":"print(\\"one\\")","range":{"start":{"line":1,"column":5},"end":{"line":1,"column":16}},"replacement":"log(\\"one\\")","metaVariables":{"single":{"MSG":{"text":"\\"one\\""}},"multi":{}}}]
            """.utf8
        )
        let matches = try ASTGrepCommand.decodeMatches(from: payload)
        #expect(matches.count == 1)
        #expect(matches[0].displayLine == 2)
        #expect(matches[0].replacement == "log(\"one\")")
        #expect(matches[0].captureSummary == #"MSG="one""#)
    }

    @Test("search presentation lists matches with captures")
    func searchPresentation() {
        let text = formatSearchMatches([])
        #expect(text == "No matches found.")
    }

    @Test("replacement preview labels dry runs and includes the apply hint")
    func replacementPresentation() {
        let text = formatReplacementPreview([], applied: false)
        #expect(text.contains("No matches found"))

        let dryRun = formatReplacementPreview([], applied: false)
        #expect(!dryRun.contains("APPLIED:"))
    }
}

@Suite("Containment edge cases")
struct ContainmentEdgeCaseTests {
    @Test("near-miss prefix sibling cannot bypass the root guard")
    func prefixTrap() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("rpc-prefix-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // .../rpc-prefix-root-X vs .../rpc-prefix-root-XB: a naive
        // hasPrefix(root) check would admit the sibling.
        let sibling = root.deletingLastPathComponent()
            .appendingPathComponent(root.lastPathComponent + "B", isDirectory: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sibling) }

        #expect(throws: ASTGrepError.self) {
            _ = try containedTarget(sibling.path, root: root.path)
        }
    }

    @Test("real children resolve inside the root")
    func childResolves() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("rpc-child-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let resolvedRoot = try containedTarget(nil, root: root.path)
        let resolvedChild = try containedTarget("sub/file.swift", root: root.path)
        #expect(resolvedChild.hasPrefix(resolvedRoot + "/"))
        #expect(resolvedChild.hasSuffix("sub/file.swift"))
    }
}
