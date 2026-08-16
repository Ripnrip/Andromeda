import Foundation

/// `publish` — push composites + heatmaps to the disposable `visual/pr-<n>`
/// orphan branch. `comment` — upsert the PR comment (marker-prefixed).
public enum Publish {
    public struct Options {
        public let pr: Int
        public let repo: String   // owner/name
        public let repoRoot: URL

        public init(pr: Int, repo: String, repoRoot: URL) {
            self.pr = pr
            self.repo = repo
            self.repoRoot = repoRoot
        }

        public var branch: String { "visual/pr-\(pr)" }
        public var rawBase: String {
            "https://raw.githubusercontent.com/\(repo)/\(branch)/out"
        }
        public var branchLink: String {
            "https://github.com/\(repo)/tree/\(branch)/out"
        }
    }

    public static func publish(_ options: Options) throws {
        let root = options.repoRoot
        try Shell.runChecked(["git", "config", "user.name", "andromeda-ci"], cwd: root)
        try Shell.runChecked(["git", "config", "user.email", "ci@andromeda.local"], cwd: root)

        // Reinstalls may have touched the lockfile; never ship that churn.
        _ = try? Shell.runChecked(["git", "checkout", "-q", "--", "package-lock.json"], cwd: root)

        try Shell.runChecked(["git", "checkout", "-q", "--orphan", options.branch], cwd: root)
        _ = try Shell.runChecked(["git", "rm", "-rq", "--cached", "."], cwd: root, allowFailure: true)

        // out/ is gitignored for local runs — CI artifacts are added with -f.
        try Shell.runChecked(["git", "add", "-f", "out/composites", "out/diffs"], cwd: root)
        try Shell.runChecked(
            ["git", "commit", "-qm", "visual diff artifacts for PR #\(options.pr)"], cwd: root
        )
        try Shell.runChecked(["git", "push", "-qf", "origin", options.branch], cwd: root)
        FileHandle.standardError.write(Data("[visual-diff] published \(options.branch)\n".utf8))
    }

    public static func comment(_ options: Options) throws {
        let root = options.repoRoot
        let report = try String(contentsOf: root.appendingPathComponent("out/report.md"), encoding: .utf8)
        let changed = try String(contentsOf: root.appendingPathComponent("out/changed.txt"), encoding: .utf8)
        let body = CommentBuilder.build(
            report: report,
            changedList: changed,
            rawBase: options.rawBase,
            branchLink: options.branchLink
        )

        let existing = try listComments(pr: options.pr, repo: options.repo)
        if let id = existing.first(where: { $0.body.hasPrefix(CommentBuilder.marker) })?.id {
            try Shell.runChecked([
                "gh", "api", "--method", "PATCH",
                "repos/\(options.repo)/issues/comments/\(id)",
                "-f", "body=\(body)",
            ], cwd: root)
            FileHandle.standardError.write(Data("[visual-diff] updated comment \(id)\n".utf8))
        } else {
            try Shell.runChecked([
                "gh", "api",
                "repos/\(options.repo)/issues/\(options.pr)/comments",
                "-f", "body=\(body)",
            ], cwd: root)
            FileHandle.standardError.write(Data("[visual-diff] posted comment\n".utf8))
        }
    }

    private struct PRComment {
        let id: Int
        let body: String
    }

    private static func listComments(pr: Int, repo: String) throws -> [PRComment] {
        let result = try Shell.runChecked(
            ["gh", "api", "repos/\(repo)/issues/\(pr)/comments", "--paginate"], cwd: nil
        )
        guard let data = result.stdout.data(using: .utf8),
              let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return array.compactMap { entry in
            guard let id = entry["id"] as? Int,
                  let body = entry["body"] as? String
            else { return nil }
            return PRComment(id: id, body: body)
        }
    }
}
