import AndromedaHTTP
import AndromedaTools
import Foundation
import Testing

/// Hermetic handler. Echoes the request into a receipt so tests prove the curtain contract.
private struct StubHandler: LettaIngressHandling {
    func write(_ request: LettaIngressRequest) async throws -> LettaIngressReceipt {
        LettaIngressReceipt(
            agentID: request.agentID,
            relativePath: "system/knowledge/noted.md",
            commitSHA: "feed",
            unchanged: false
        )
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

    /// Happy path echoes agent id and does not mention the backend brand in the error-free text.
    @Test("tagged write returns a receipt")
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
        #expect(receipt.relativePath == "system/knowledge/noted.md")
        #expect(receipt.commitSHA == "feed")
        #expect(!receipt.unchanged)
        #expect(!text.lowercased().contains("letta"))
    }
}
