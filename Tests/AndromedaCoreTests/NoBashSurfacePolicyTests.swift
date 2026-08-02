import Foundation
import Testing
@testable import AndromedaCore

/// Repository policy tests for the No Bash implementation surface rule (BIN-219).
@Suite("NoBashSurfacePolicy")
struct NoBashSurfacePolicyTests {
    private let policy = NoBashSurfacePolicy()

    @Test("repository tree has no disallowed shell automation")
    func repositoryIsCompliant() throws {
        guard let root = AndromedaRepositoryRoot.resolve() else {
            Issue.record("Could not resolve repository root from \(#filePath)")
            return
        }
        let report = try policy.evaluate(repositoryRoot: root)
        if !report.violations.isEmpty {
            let detail = report.violations.map(\.description).joined(separator: "\n")
            Issue.record(
                """
                No-Bash surface violations (add to \(NoBashSurfacePolicy.allowlistRelativePath) only with explicit approval, or delete the files):
                \(detail)
                """
            )
        }
        #expect(report.isCompliant)
    }

    @Test("canary: scripts/oops.sh fails when not allowlisted")
    func canaryUnallowlistedShellFails() {
        let report = policy.evaluate(
            relativePaths: ["scripts/oops.sh", "Sources/AndromedaCore/Version.swift"],
            allowlisted: []
        )
        #expect(!report.isCompliant)
        #expect(report.violations.contains { $0.relativePath == "scripts/oops.sh" })
    }

    @Test("canary: allowlisted shell path is accepted")
    func canaryAllowlistedShellPasses() {
        let report = policy.evaluate(
            relativePaths: ["legacy/grandfathered.sh"],
            allowlisted: ["legacy/grandfathered.sh"]
        )
        #expect(report.isCompliant)
    }

    @Test("bash shebang without .sh extension is rejected unless allowlisted")
    func bashShebangWithoutExtensionFails() {
        let report = policy.evaluate(
            relativePaths: ["Tools/do-thing"],
            fileContents: ["Tools/do-thing": "#!/usr/bin/env bash\necho hi\n"],
            allowlisted: []
        )
        #expect(!report.isCompliant)
        #expect(report.violations.contains { $0.relativePath == "Tools/do-thing" })
    }

    @Test("python shebang is not treated as bash surface")
    func pythonShebangAllowed() {
        let report = policy.evaluate(
            relativePaths: ["Tools/no_bash_surface_gate.py"],
            fileContents: [
                "Tools/no_bash_surface_gate.py": "#!/usr/bin/env python3\nprint('ok')\n"
            ],
            allowlisted: []
        )
        #expect(report.isCompliant)
    }

    @Test("allowlist parser ignores comments and blank lines")
    func allowlistParsing() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("andromeda-allowlist-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let file = temp.appendingPathComponent("allowlist.txt")
        try """
        # comment

        legacy/a.sh
        ./legacy/b.sh
        """.write(to: file, atomically: true, encoding: .utf8)

        let paths = try policy.loadAllowlist(from: file)
        #expect(paths == Set(["legacy/a.sh", "legacy/b.sh"]))
    }

    @Test("hasBashShebang recognizes common forms")
    func shebangDetection() {
        #expect(policy.hasBashShebang("#!/bin/bash\n"))
        #expect(policy.hasBashShebang("#!/usr/bin/env bash\n"))
        #expect(policy.hasBashShebang("#! /usr/bin/env bash\n"))
        #expect(!policy.hasBashShebang("#!/usr/bin/env python3\n"))
        #expect(!policy.hasBashShebang("echo hi\n"))
    }
}
