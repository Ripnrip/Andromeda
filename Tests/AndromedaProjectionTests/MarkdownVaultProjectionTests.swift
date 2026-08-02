import AndromedaDomain
import AndromedaMemory
import Foundation
import Testing

@testable import AndromedaProjections

@Suite("AndromedaProjections.MarkdownVaultProjection")
struct MarkdownVaultProjectionTests {
    @Test("writes Obsidian-compatible front matter and body")
    func frontMatterAndBody() async throws {
        let directory = try makeTemporaryDirectory()
        let projection = MarkdownVaultProjection(vaultDirectoryURL: directory)
        let record = makeRecord(privacy: .project, tags: ["runtime", "journal"])

        _ = try await projection.write(record: record)

        let fileURL = directory.appendingPathComponent("\(record.memoryID.description).md")
        let contents = try String(contentsOf: fileURL, encoding: .utf8)

        #expect(contents.contains("---"))
        #expect(contents.contains("id: \(record.memoryID.description)"))
        #expect(contents.contains("kind: \(record.kind.rawValue)"))
        #expect(contents.contains("privacy: project"))
        #expect(contents.contains("- runtime"))
        #expect(contents.contains("- journal"))
        #expect(contents.contains("checksum: \(record.checksum)"))
        #expect(contents.contains("# \(record.summary)"))
        #expect(contents.contains(record.content))
        #expect(contents.contains("#runtime #journal"))
    }

    @Test("rejects private memories")
    func privateMemoryRejected() async throws {
        let directory = try makeTemporaryDirectory()
        let projection = MarkdownVaultProjection(vaultDirectoryURL: directory)
        let record = makeRecord(privacy: .private)

        #expect(projection.accepts(record) == false)
    }

    @Test("writes atomically so the destination file is never partial")
    func atomicWrite() async throws {
        let directory = try makeTemporaryDirectory()
        let projection = MarkdownVaultProjection(vaultDirectoryURL: directory)
        let record = makeRecord(privacy: .project)

        _ = try await projection.write(record: record)

        let fileURL = directory.appendingPathComponent("\(record.memoryID.description).md")
        let tempDirectory = directory.appendingPathComponent(".tmp")

        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(contents.hasPrefix("---"))
        #expect(!contents.contains("\0"))

        // The temp directory may exist but must not contain stale temp files.
        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            let temps = try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path)
            #expect(temps.isEmpty)
        }
    }

    private func makeRecord(privacy: PrivacyLevel, tags: [String] = ["test"]) -> MemoryRecord {
        MemoryRecord(
            memoryID: MemoryID(rawValue: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1")!),
            eventID: EventID(rawValue: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1")!),
            correlationID: UUID(uuidString: "cccccccc-cccc-cccc-cccc-ccccccccccc1")!,
            scope: EventScope(
                projectID: ProjectID(rawValue: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!),
                sessionID: SessionID(rawValue: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)
            ),
            source: MemorySource(subsystem: "tests", actor: "projection", label: "markdown"),
            kind: .decision,
            privacyLevel: privacy,
            summary: "Atomic write decision",
            content: "The vault projection must write complete files only.",
            tags: tags,
            metadata: ["area": "vault"],
            relatedContext: [:],
            checksum: "sha256:abc123",
            createdAt: Date(timeIntervalSince1970: 1_722_000_000)
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
