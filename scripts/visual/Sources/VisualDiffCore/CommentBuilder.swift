import Foundation

/// Builds the upserted PR comment body from a diff run's outputs.
public enum CommentBuilder {
    public static let marker = "<!-- web-visual-diff -->"
    public static let embedCap = 8

    /// - Parameters:
    ///   - report: contents of `out/report.md` (the markdown verdict table).
    ///   - changedList: contents of `out/changed.txt` (composite files, evidence order).
    ///   - rawBase: raw.githubusercontent base URL for the artifacts branch.
    ///   - branchLink: browsable URL for the artifacts branch.
    public static func build(
        report: String,
        changedList: String,
        rawBase: String,
        branchLink: String
    ) -> String {
        var body = """
        \(marker)
        \(report.trimmed())

        ### Left–right strips (base | head)

        """

        let entries = changedList
            .split(separator: "\n")
            .map { String($0).trimmed() }
            .filter { !$0.isEmpty }

        var embedded = 0
        for name in entries {
            if embedded < embedCap {
                body += "#### \(name)\n\n![diff: \(name)](\(rawBase)/composites/\(name))\n\n"
                embedded += 1
            } else {
                body += "- [\(name)](\(rawBase)/composites/\(name))\n"
            }
        }

        body += """

        _Heatmap overlays on the [artifacts branch](\(branchLink)) · full-size shots in workflow artifacts · regenerated on every push._
        """
        return body
    }
}
