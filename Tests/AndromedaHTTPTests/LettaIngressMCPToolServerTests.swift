import AndromedaHTTP
import AndromedaTools
import Foundation
import Testing

/// Hermetic handler. Echoes the request into a curtain-safe receipt.
private struct StubHandler: LettaIngressHandling {
    let failure: (any Error)?

    init(failure: (any Error)? = nil) {
        self.failure = failure
    }

    func write(_ request: LettaIngressRequest) async throws -> LettaIngressReceipt {
        if let failure { throw failure }
        return LettaIngressReceipt(
            agentID: request.agentID,
            unchanged: false
        )
    }
}

/// Handler that pretends a backend leak slipped through as LocalizedError.
private struct LeakyBackendError: LocalizedError {
    var errorDescription: String? {
        "git commit failed: /Users/admin/.letta/lc-local-backend/memfs/agent-1/memory"
    }
}

@Suite("AndromedaHTTP.LettaIngressMCPToolServer")
struct LettaIngressMCPToolServerTests {
    /// The advertised name must stay brand-free.
    @Test("lists memory.ingress and not a backend brand")
    func listsCurtainName() async {
        let server = LettaIngressMCPToolServer(handler: StubHandler())
        let names = await server.listTools().map(\.name)
        #expect(names == ["memory.ingress"])
        #expect(!names.joined().lowercased().contains("letta"))
    }

    /// A tagged write returns a receipt. Missing visibility is an error, not a silent store.
    @Test("rejects a write that omits the visibility tag")
    func rejectsUntagged() async {
        let server = LettaIngressMCPToolServer(handler: StubHandler())
        let result = await server.callTool(name: "memory.ingress", arguments: [
            "agent_id": .string("agent-1"),
            "title": .string("Note"),
            "body": .string("body"),
        ])
        #expect(result.isError)
        #expect(result.content.first?.text.contains("visibility") == true)
    }

    /// Happy path echoes agent id and never returns memfs path or commit SHA.
    @Test("tagged write returns an opaque receipt")
    func taggedWrite() async throws {
        let server = LettaIngressMCPToolServer(handler: StubHandler())
        let result = await server.callTool(name: "memory.ingress", arguments: [
            "agent_id": .string("agent-1"),
            "title": .string("Note"),
            "body": .string("body"),
            "visibility": .string("internal"),
        ])
        #expect(!result.isError)
        let text = try #require(result.content.first?.text)
        let receipt = try JSONDecoder().decode(LettaIngressReceipt.self, from: Data(text.utf8))
        #expect(receipt.agentID == "agent-1")
        #expect(!receipt.unchanged)
        #expect(!text.contains("relativePath"))
        #expect(!text.contains("commitSHA"))
        #expect(!text.contains("system/knowledge"))
        #expect(!text.lowercased().contains("letta"))
    }

    /// Backend failures cross the curtain as error_code only — never localizedDescription.
    @Test("backend failure returns error_code without path or stderr")
    func backendFailureIsOpaque() async throws {
        let server = LettaIngressMCPToolServer(
            handler: StubHandler(failure: IngressBackendError(errorCode: "memfs_missing"))
        )
        let result = await server.callTool(name: "memory.ingress", arguments: [
            "agent_id": .string("agent-1"),
            "title": .string("Note"),
            "body": .string("body"),
            "visibility": .string("internal"),
        ])
        #expect(result.isError)
        let text = try #require(result.content.first?.text)
        #expect(text.contains(#""error_code":"ingress_failed""#))
        #expect(!text.contains("memfs"))
        #expect(!text.contains("git"))
        #expect(!text.contains("/Users/"))
        #expect(!text.contains("lc-local-backend"))
        #expect(!text.contains("stderr"))
        #expect(!text.contains("Memory ingress failed"))
    }

    /// Request-shaped codes stay specific. Only storage brands collapse.
    @Test("request codes pass and git_failed collapses")
    func clientCodesStayNeutral() {
        #expect(IngressBackendError.clientCode(from: "empty_title") == "empty_title")
        #expect(IngressBackendError.clientCode(from: "git_failed") == "ingress_failed")
        #expect(IngressBackendError.clientCode(from: "verification_failed") == "verification_failed")
    }

    /// A raw LocalizedError must not forward path/stderr through the curtain.
    @Test("untyped LocalizedError collapses to ingress_failed")
    func untypedFailureIsCollapsed() async throws {
        let server = LettaIngressMCPToolServer(
            handler: StubHandler(failure: LeakyBackendError())
        )
        let result = await server.callTool(name: "memory.ingress", arguments: [
            "agent_id": .string("agent-1"),
            "title": .string("Note"),
            "body": .string("body"),
            "visibility": .string("internal"),
        ])
        #expect(result.isError)
        let text = try #require(result.content.first?.text)
        #expect(text.contains(#""error_code":"ingress_failed""#))
        #expect(!text.contains("/Users/admin"))
        #expect(!text.contains("lc-local-backend"))
        #expect(!text.contains("git commit failed"))
    }
}
