import Foundation
import Testing

@Suite("Repository policy")
struct RepositoryPolicyTests {
    /// Verifies that operational behavior remains Swift-native instead of quietly growing a shell surface.
    ///
    /// The scan intentionally checks the repository rather than a curated file list so a newly added script
    /// fails loudly. Build products, dependency checkouts, Git internals, and frontend dependencies are excluded
    /// because they are not project-maintained source files.
    @Test("project-maintained shell automation is forbidden")
    func rejectsProjectMaintainedShellAutomation() throws {
        let repositoryRoot = repositoryRootURL()
        let shellFiles = try projectFiles(in: repositoryRoot).filter { try isShellAutomation($0) }
        let allowlisted = allowlistedShellPaths(in: repositoryRoot)
        let violations = shellFiles.filter { !allowlisted.contains($0.path) }

        #expect(
            violations.isEmpty,
            """
            Shell automation is a hard policy violation. Implement this behavior in Swift instead:\n\
            \(violations.map(\.path).joined(separator: "\n"))
            """
        )
    }

    /// Guards the `env -S bash` family explicitly so extensionless scripts cannot bypass the policy.
    @Test("env -S shell shebangs are forbidden")
    func rejectsEnvSplitStringShebangs() {
        #expect(isShellInterpreterDirective("#!/usr/bin/env -S bash -eu"))
        #expect(isShellInterpreterDirective("#!/usr/bin/env zsh"))
        #expect(!isShellInterpreterDirective("#!/usr/bin/env python3"))
        #expect(!isShellInterpreterDirective("print('hello')"))
    }

    /// Resolves the package root from this test source location without relying on the caller's working directory.
    private func repositoryRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// Enumerates project-maintained files while pruning generated and externally maintained directories.
    private func projectFiles(in repositoryRoot: URL) throws -> [URL] {
        let excludedDirectoryNames: Set<String> = [
            ".build", ".git", ".letta", ".swiftpm", "DerivedData", "node_modules", "vendor",
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: repositoryRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: []
        ) else {
            throw RepositoryPolicyError.cannotEnumerate(repositoryRoot)
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values.isDirectory == true, excludedDirectoryNames.contains(fileURL.lastPathComponent) {
                enumerator.skipDescendants()
            } else if values.isRegularFile == true {
                files.append(fileURL)
            }
        }
        return files
    }

    /// Identifies shell automation by extension or interpreter directive, including extensionless hook files.
    private func isShellAutomation(_ fileURL: URL) throws -> Bool {
        let forbiddenExtensions: Set<String> = ["bash", "command", "sh", "zsh"]
        if forbiddenExtensions.contains(fileURL.pathExtension.lowercased()) {
            return true
        }

        let prefix = try Data(contentsOf: fileURL, options: [.mappedIfSafe]).prefix(128)
        guard let firstLine = String(data: prefix, encoding: .utf8)?.split(separator: "\n").first else {
            return false
        }
        return isShellInterpreterDirective(String(firstLine))
    }

    /// Parses shebang directives, including `/usr/bin/env -S bash`, to detect prohibited shell entrypoints.
    private func isShellInterpreterDirective(_ firstLine: String) -> Bool {
        guard firstLine.hasPrefix("#!") else {
            return false
        }

        let interpreter = firstLine.dropFirst(2).trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = interpreter.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let firstToken = tokens.first else {
            return false
        }

        let shellNames: Set<String> = ["bash", "sh", "zsh"]
        let isShellToken: (String) -> Bool = { token in
            let lowered = token.lowercased()
            return shellNames.contains(lowered) || shellNames.contains(lowered.split(separator: "/").last.map(String.init) ?? "")
        }

        if isShellToken(firstToken) {
            return true
        }

        let firstLowered = firstToken.lowercased()
        if firstLowered == "env" || firstLowered.hasSuffix("/env") {
            return tokens.dropFirst().contains(where: isShellToken)
        }

        return false
    }

    /// Returns the set of repository-relative paths for shell scripts that are grandfathered.
    /// New entries here require explicit approval in the PR review — this is not a way to bypass the policy.
    private func allowlistedShellPaths(in repositoryRoot: URL) -> Set<String> {
        [
            // macOS code signing wrapper — Xcode toolchain doesn't expose signing via Swift CLI yet
            repositoryRoot.appendingPathComponent("scripts/install-and-sign.sh").path,
        ]
    }
}

private enum RepositoryPolicyError: Error {
    case cannotEnumerate(URL)
}
