import Foundation

/// Rewrites Studio-home LaunchAgent templates to the installing user's absolute `$HOME`.
///
/// launchd does **not** expand `$HOME`/`~` — install must emit absolute paths only.
public enum LaunchAgentPlistRenderer {
    /// Renders `template` by replacing the Studio home string with `homeDirectory`.
    public static func render(
        template: String,
        studioHome: String = StudioHomeTemplate.path,
        homeDirectory: String
    ) throws -> String {
        guard !homeDirectory.isEmpty else {
            throw InstallError.missingHome
        }
        if studioHome != homeDirectory, !template.contains(studioHome) {
            throw InstallError.plistTemplateMissingStudioHome(
                path: "(in-memory)",
                studioHome: studioHome
            )
        }
        return template.replacingOccurrences(of: studioHome, with: homeDirectory)
    }

    /// Reads a plist template from disk and writes the rewritten form to `destination`.
    public static func renderFile(
        source: URL,
        destination: URL,
        studioHome: String = StudioHomeTemplate.path,
        homeDirectory: String,
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: source.path) else {
            throw InstallError.missingPlistTemplate(source.path)
        }
        let template = try String(contentsOf: source, encoding: .utf8)
        if studioHome != homeDirectory, !template.contains(studioHome) {
            throw InstallError.plistTemplateMissingStudioHome(
                path: source.path,
                studioHome: studioHome
            )
        }
        let rendered = try render(
            template: template,
            studioHome: studioHome,
            homeDirectory: homeDirectory
        )
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try rendered.write(to: destination, atomically: true, encoding: .utf8)
    }
}
