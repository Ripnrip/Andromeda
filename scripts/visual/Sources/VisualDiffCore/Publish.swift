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

        // Publish through git plumbing with a temporary index
        // (`GIT_INDEX_FILE`) — the orphan tree is built without touching the
        // working tree at all. The porcelain `checkout --orphan` flow mutates
        // the live checkout (clearing its index and stranding later steps on
        // a tree that contains only `out/`); plumbing keeps the runner's own
        // sources, `.build`, and any untracked state intact.
        let tmpIndex = NSTemporaryDirectory() + "visual-diff-\(UUID().uuidString).index"
        defer { try? FileManager.default.removeItem(atPath: tmpIndex) }
        let indexEnv = ["GIT_INDEX_FILE": tmpIndex]

        try Shell.runChecked(["git", "read-tree", "--empty"], cwd: root, environment: indexEnv)
        // out/ is gitignored for local runs — CI artifacts are added with -f.
        try Shell.runChecked(
            ["git", "add", "-f", "out/composites", "out/diffs"], cwd: root, environment: indexEnv
        )
        let tree = try Shell.runChecked(["git", "write-tree"], cwd: root, environment: indexEnv)
            .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let commit = try Shell.runChecked(
            ["git", "commit-tree", tree, "-m", "visual diff artifacts for PR #\(options.pr)"],
            cwd: root
        ).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        try Shell.runChecked(
            ["git", "update-ref", "refs/heads/\(options.branch)", commit], cwd: root
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
