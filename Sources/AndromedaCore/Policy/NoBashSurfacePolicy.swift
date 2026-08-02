import Foundation

/// Enforces Andromeda's "No Bash implementation surface" charter rule.
///
/// Scans a repository tree for committed shell automation (`*.sh` and
/// bash-shebang scripts) and reports any path not present on the explicit
/// allowlist. Agents and CI must fail closed — docs alone are not enough.
///
/// - Invariants: allowlist paths are repo-relative with `/` separators;
///   scan skips build/vendor caches; markdown fenced `bash` examples are not files.
/// - Concurrency: value type, `Sendable`.
/// - Privacy: reports paths only; never reads secret file contents into logs beyond the shebang line.
public struct NoBashSurfacePolicy: Sendable {
    /// Relative path of the canonical allowlist inside the repo.
    public static let allowlistRelativePath = "config/shell-allowlist.txt"

    /// Directory name segments skipped while walking the tree.
    public static let skippedDirectoryNames: Set<String> = [
        ".git",
        ".build",
        ".swiftpm",
        "DerivedData",
        "node_modules",
        ".venv",
        "venv",
        "__pycache__",
    ]

    /// Filename suffixes treated as shell scripts regardless of shebang.
    public static let shellExtensions: Set<String> = ["sh", "bash"]

    public struct Violation: Equatable, Sendable, CustomStringConvertible {
        public let relativePath: String
        public let reason: String

        public init(relativePath: String, reason: String) {
            self.relativePath = relativePath
            self.reason = reason
        }

        public var description: String {
            "\(relativePath): \(reason)"
        }
    }

    public struct Report: Equatable, Sendable {
        public let allowlistPath: String
        public let allowlistedPaths: [String]
        public let violations: [Violation]

        public var isCompliant: Bool { violations.isEmpty }
    }

    public init() {}

    /// Loads allowlisted relative paths from the allowlist file.
    ///
    /// Blank lines and `#` comments are ignored. Paths are normalized to
    /// forward-slash form without a leading `./`.
    public func loadAllowlist(from allowlistFile: URL) throws -> Set<String> {
        let contents = try String(contentsOf: allowlistFile, encoding: .utf8)
        var paths = Set<String>()
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            paths.insert(normalizeRelativePath(trimmed))
        }
        return paths
    }

    /// Scans `repositoryRoot` for disallowed shell automation.
    public func evaluate(repositoryRoot: URL) throws -> Report {
        let allowlistURL = repositoryRoot.appendingPathComponent(Self.allowlistRelativePath)
        let allowlisted = try loadAllowlist(from: allowlistURL)
        let violations = try findViolations(repositoryRoot: repositoryRoot, allowlisted: allowlisted)
        return Report(
            allowlistPath: Self.allowlistRelativePath,
            allowlistedPaths: allowlisted.sorted(),
            violations: violations.sorted { $0.relativePath < $1.relativePath }
        )
    }

    /// Evaluates an in-memory file map (used by canary / unit tests).
    ///
    /// - Parameters:
    ///   - relativePaths: repo-relative paths present in a synthetic tree.
    ///   - fileContents: optional first-line content keyed by relative path (for shebang checks).
    ///   - allowlisted: explicit allowlist set.
    public func evaluate(
        relativePaths: [String],
        fileContents: [String: String] = [:],
        allowlisted: Set<String>
    ) -> Report {
        var violations: [Violation] = []
        for rawPath in relativePaths {
            let path = normalizeRelativePath(rawPath)
            if isShellExtensionPath(path) {
                if !allowlisted.contains(path) {
                    violations.append(
                        Violation(
                            relativePath: path,
                            reason: "shell script extension is not on \(Self.allowlistRelativePath)"
                        )
                    )
                }
                continue
            }
            if let contents = fileContents[path] ?? fileContents[rawPath],
               hasBashShebang(contents)
            {
                if !allowlisted.contains(path) {
                    violations.append(
                        Violation(
                            relativePath: path,
                            reason: "bash shebang script is not on \(Self.allowlistRelativePath)"
                        )
                    )
                }
            }
        }
        return Report(
            allowlistPath: Self.allowlistRelativePath,
            allowlistedPaths: allowlisted.sorted(),
            violations: violations.sorted { $0.relativePath < $1.relativePath }
        )
    }

    /// Returns true when text begins with a bash shebang.
    public func hasBashShebang(_ contents: String) -> Bool {
        let firstLine = contents
            .split(separator: "\n", omittingEmptySubsequences: false)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? ""
        let normalized = firstLine.lowercased()
        return normalized.hasPrefix("#!/bin/bash")
            || normalized.hasPrefix("#!/usr/bin/env bash")
            || normalized.hasPrefix("#! /bin/bash")
            || normalized.hasPrefix("#! /usr/bin/env bash")
    }

    // MARK: - Private

    private func findViolations(repositoryRoot: URL, allowlisted: Set<String>) throws -> [Violation] {
        let rootPath = repositoryRoot.standardizedFileURL.path
        var violations: [Violation] = []
        let enumerator = FileManager.default.enumerator(
            at: repositoryRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        // Re-include allowlisted config / hooks that may be hidden (.githooks).
        // Hidden skip above drops `.githooks`; walk that tree explicitly if present.
        var urls: [URL] = []
        while let item = enumerator?.nextObject() as? URL {
            let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values.isDirectory == true {
                if Self.skippedDirectoryNames.contains(item.lastPathComponent) {
                    enumerator?.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true else { continue }
            urls.append(item)
        }
        let gitHooks = repositoryRoot.appendingPathComponent(".githooks")
        if FileManager.default.fileExists(atPath: gitHooks.path) {
            let hookEnumerator = FileManager.default.enumerator(
                at: gitHooks,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey]
            )
            while let item = hookEnumerator?.nextObject() as? URL {
                let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                if values.isDirectory == true { continue }
                guard values.isRegularFile == true else { continue }
                urls.append(item)
            }
        }

        for fileURL in urls {
            let absolute = fileURL.standardizedFileURL.path
            guard absolute.hasPrefix(rootPath) else { continue }
            var relative = String(absolute.dropFirst(rootPath.count))
            if relative.hasPrefix("/") {
                relative = String(relative.dropFirst())
            }
            relative = normalizeRelativePath(relative)

            if isShellExtensionPath(relative) {
                if !allowlisted.contains(relative) {
                    violations.append(
                        Violation(
                            relativePath: relative,
                            reason: "shell script extension is not on \(Self.allowlistRelativePath)"
                        )
                    )
                }
                continue
            }

            // Shebang check: only read a small prefix.
            guard let handle = try? FileHandle(forReadingFrom: fileURL) else { continue }
            defer { try? handle.close() }
            let prefixData: Data
            do {
                prefixData = try handle.read(upToCount: 256) ?? Data()
            } catch {
                continue
            }
            guard let prefix = String(data: prefixData, encoding: .utf8) else { continue }
            if hasBashShebang(prefix), !allowlisted.contains(relative) {
                violations.append(
                    Violation(
                        relativePath: relative,
                        reason: "bash shebang script is not on \(Self.allowlistRelativePath)"
                    )
                )
            }
        }
        return violations
    }

    private func isShellExtensionPath(_ relativePath: String) -> Bool {
        let ext = URL(fileURLWithPath: relativePath).pathExtension.lowercased()
        return Self.shellExtensions.contains(ext)
    }

    private func normalizeRelativePath(_ path: String) -> String {
        var value = path.replacingOccurrences(of: "\\", with: "/")
        while value.hasPrefix("./") {
            value = String(value.dropFirst(2))
        }
        if value.hasPrefix("/") {
            value = String(value.dropFirst())
        }
        return value
    }
}

/// Locates the repository root by walking parents from a starting file URL
/// until `Package.swift` and the shell allowlist are both present.
public enum AndromedaRepositoryRoot {
    public static func resolve(startingAt fileURL: URL = URL(fileURLWithPath: #filePath)) -> URL? {
        var directory = fileURL.deletingLastPathComponent()
        let fm = FileManager.default
        for _ in 0..<16 {
            let package = directory.appendingPathComponent("Package.swift")
            let allowlist = directory.appendingPathComponent(NoBashSurfacePolicy.allowlistRelativePath)
            if fm.fileExists(atPath: package.path), fm.fileExists(atPath: allowlist.path) {
                return directory
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path {
                break
            }
            directory = parent
        }
        return nil
    }
}
