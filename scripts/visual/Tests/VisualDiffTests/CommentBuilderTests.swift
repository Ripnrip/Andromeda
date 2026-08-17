import Testing
import Foundation
@testable import VisualDiffCore

@Suite("CommentBuilder")
struct CommentBuilderTests {
    private func makeBody(entries: [String]) -> String {
        CommentBuilder.build(
            report: "## report\n\n| a |\n",
            changedList: entries.joined(separator: "\n"),
            rawBase: "https://raw.example/base",
            branchLink: "https://github.com/ex/repo/tree/visual/pr-1/out"
        )
    }

    @Test("starts with the machine marker so upsert can find it")
    func markerPrefix() {
        #expect(makeBody(entries: ["a.png"]).hasPrefix(CommentBuilder.marker))
    }

    @Test("embeds up to the cap, links the rest")
    func embedCap() {
        let entries = (0..<12).map { "shot-\($0).png" }
        let body = makeBody(entries: entries)
        let embeds = body.components(separatedBy: "![diff:").count - 1
        let links = body.components(separatedBy: "- [shot-").count - 1
        #expect(embeds == CommentBuilder.embedCap)
        #expect(links == entries.count - CommentBuilder.embedCap)
    }

    @Test("zero changed entries still renders report and footer")
    func emptyList() {
        let body = makeBody(entries: [])
        #expect(body.contains("## report"))
        #expect(body.contains("artifacts branch"))
    }

    @Test("embedded URLs point at the raw base under composites/")
    func rawUrls() {
        let body = makeBody(entries: ["design--desktop.png"])
        #expect(body.contains("(https://raw.example/base/composites/design--desktop.png)"))
    }
}

@Suite("FlagParser")
struct FlagParserTests {
    @Test("require returns the value after the flag")
    func requirePresent() throws {
        let value = try FlagParser.require("--port", arguments: ["--side", "base", "--port", "4173"])
        #expect(value == "4173")
    }

    @Test("require throws on a missing flag")
    func requireMissing() {
        #expect(throws: CLIError.self) {
            _ = try FlagParser.require("--missing", arguments: ["--other", "1"])
        }
    }

    @Test("optional falls back to the default")
    func optionalDefault() {
        let value = FlagParser.optional("--absent", arguments: ["x"], default: "fallback")
        #expect(value == "fallback")
    }
}

@Suite("Tooling")
struct ToolingTests {
    private func makeToolingDir() throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("visual-tooling-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: root.appendingPathComponent("shot.mjs").path, contents: Data()
        )
        return root.path
    }

    @Test("resolves the package root from a release binary path")
    func resolves() throws {
        let tooling = try makeToolingDir()
        let dir = Tooling.directory(
            executablePath: "\(tooling)/.build/release/visual-diff",
            fallback: "/default"
        )
        #expect(dir == tooling)
        try? FileManager.default.removeItem(atPath: tooling)
    }

    @Test("falls back when sibling scripts are absent")
    func fallback() {
        let dir = Tooling.directory(
            executablePath: "/nowhere/.build/release/visual-diff",
            fallback: "/default"
        )
        #expect(dir == "/default")
    }
}
