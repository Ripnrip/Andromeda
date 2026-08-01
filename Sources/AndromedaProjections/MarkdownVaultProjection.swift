import AndromedaDomain
import AndromedaMemory
import Foundation

/// Writes one Obsidian-compatible Markdown file per accepted memory.
///
/// The sink rejects private memories so they never reach the vault. Each
/// write is performed atomically by writing to a sibling temp file and
/// replacing the destination.
public actor MarkdownVaultProjection: MemoryProjectionSink {
    public nonisolated let sinkID = "memory.projection.markdown.vault"
    public nonisolated let schemaVersion = "memory.projection.markdown.v1"

    private let vaultDirectoryURL: URL

    /// Creates a vault projection that writes into `vaultDirectoryURL`.
    ///
    /// The directory is created on first write if it does not exist.
    public init(vaultDirectoryURL: URL) {
        self.vaultDirectoryURL = vaultDirectoryURL
    }

    public nonisolated func accepts(_ record: MemoryRecord) -> Bool {
        record.privacyLevel != .private
    }

    public func write(record: MemoryRecord) async throws -> MemoryWriteReceipt {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: vaultDirectoryURL, withIntermediateDirectories: true)

        let filename = "\(record.memoryID.description).md"
        let destinationURL = vaultDirectoryURL.appendingPathComponent(filename)
        let tempURL = vaultDirectoryURL
            .appendingPathComponent(".tmp")
            .appendingPathComponent("\(filename).\(UUID().uuidString).tmp")

        try fileManager.createDirectory(at: tempURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let markdown = Self.renderMarkdown(for: record)
        try markdown.write(to: tempURL, atomically: false, encoding: .utf8)

        _ = try fileManager.replaceItemAt(destinationURL, withItemAt: tempURL)

        return MemoryWriteReceipt(
            memoryID: record.memoryID,
            sinkID: sinkID,
            schemaVersion: schemaVersion,
            checksum: record.checksum,
            status: .committed,
            verification: .pending
        )
    }

    private static func renderMarkdown(for record: MemoryRecord) -> String {
        let frontMatter = renderFrontMatter(for: record)
        let body = renderBody(for: record)
        return frontMatter + "\n" + body
    }

    private static func renderFrontMatter(for record: MemoryRecord) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var lines: [String] = []
        lines.append("---")
        lines.append("id: \(record.memoryID.description)")
        lines.append("kind: \(record.kind.rawValue)")
        lines.append("privacy: \(record.privacyLevel.rawValue)")
        lines.append("tags:")
        for tag in record.tags {
            lines.append("  - \(tag)")
        }
        lines.append("created: \(formatter.string(from: record.createdAt))")
        lines.append("checksum: \(record.checksum)")
        lines.append("---")
        return lines.joined(separator: "\n")
    }

    private static func renderBody(for record: MemoryRecord) -> String {
        var components: [String] = []
        components.append("# \(record.summary)")
        components.append("")
        components.append(record.content)
        if !record.tags.isEmpty {
            components.append("")
            components.append(record.tags.map { "#\($0)" }.joined(separator: " "))
        }
        return components.joined(separator: "\n")
    }
}
