import Foundation

enum Statusline {
    /// Pure render. No I/O — feed it already-resolved model / path / branch.
    static func line(model: String, directory: String, branch: String?) -> String {
        let parts = ["✦ \(model)", directory] + [branch.map { "⑂ \($0)" }].compactMap { $0 }
        return parts.joined(separator: "  ·  ")
    }

    static func shortenedPath(_ path: String, home: String) -> String {
        guard !home.isEmpty, path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
