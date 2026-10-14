import Foundation
import Testing
@testable import andromeda_statusline

@Suite("Statusline")
struct StatuslineTests {
    @Test("renders model, shortened home path, and branch")
    func rendersFullLine() {
        let line = Statusline.line(
            model: "Opus",
            directory: Statusline.shortenedPath("/Users/admin/Developer/Andromeda", home: "/Users/admin"),
            branch: "feat/andromeda-mcp"
        )
        #expect(line == "✦ Opus  ·  ~/Developer/Andromeda  ·  ⑂ feat/andromeda-mcp")
    }

    @Test("omits branch when nil")
    func omitsMissingBranch() {
        let line = Statusline.line(model: "Opus", directory: "/tmp", branch: nil)
        #expect(line == "✦ Opus  ·  /tmp")
        #expect(!line.contains("⑂"))
    }

    @Test("leaves paths outside home untouched")
    func leavesForeignPaths() {
        #expect(Statusline.shortenedPath("/tmp/work", home: "/Users/admin") == "/tmp/work")
    }

    @Test("decodes Claude Code snake_case payload")
    func decodesPayload() throws {
        let json = Data(#"""
        {"model":{"display_name":"Opus"},"workspace":{"current_dir":"/Users/admin/Developer/Andromeda"}}
        """#.utf8)
        let payload = try #require(StatusPayloadDecoder.decode(json))
        #expect(payload.model?.displayName == "Opus")
        #expect(payload.workspace?.currentDir == "/Users/admin/Developer/Andromeda")
    }

    @Test("garbage stdin degrades to an empty payload, not a crash")
    func garbageIsNil() {
        #expect(StatusPayloadDecoder.decode(Data("not-json".utf8)) == nil)
    }

    /// A wrong-typed field must name the coding path instead of a silent nil.
    @Test("wrong-typed model keeps the coding path")
    func wrongTypeKeepsPath() {
        let result = StatusPayloadDecoder.evidence(Data(#"{"model":1}"#.utf8))
        guard case let .failure(failure) = result else {
            Issue.record("expected a decode failure")
            return
        }
        #expect(failure.evidence.contains("model"))
        #expect(!failure.evidence.isEmpty)
    }
}
