// Tools.swift — capability-neutral tool surface: schemas, typed arguments,
// and pure presentation of results.
//
// Clients see `code.search` / `code.replace` capability IDs. The ast-grep
// engine behind them stays behind the server boundary (repo AGENTS.md,
// capability-hiding law).

import Foundation

// MARK: - Tool catalog

struct Tool: Encodable, Sendable {
    struct Property: Encodable, Sendable {
        let type: String
        let description: String
    }

    struct InputSchema: Encodable, Sendable {
        let type = "object"
        let properties: [String: Property]
        let required: [String]
    }

    let name: String
    let description: String
    let inputSchema: InputSchema

    static let search = Tool(
        name: "code.search",
        description: """
            Search for code patterns using AST matching. More precise than text search.

            Use meta-variables in patterns:
            - $NAME - matches any single AST node (identifier, expression, etc.)
            - $$$ARGS - matches multiple nodes (for function arguments, list items, etc.)

            Examples:
            - "func $NAME($$$ARGS)" - find all function declarations
            - "print($MSG)" - find all print calls
            - "$X === nil" - find nil equality checks

            Note: Patterns must be valid AST nodes for the language.
            """,
        inputSchema: InputSchema(
            properties: [
                "pattern": Property(
                    type: "string",
                    description: "AST pattern with meta-variables ($X, $$$ARGS)"
                ),
                "path": Property(
                    type: "string",
                    description: "File or directory to search, resolved under the workspace root (default: root). Paths resolving outside the root are rejected."
                ),
                "language": Property(
                    type: "string",
                    description: "Language hint when file extension is ambiguous (swift, python, javascript, …)"
                ),
            ],
            required: ["pattern"]
        )
    )

    static let replacement = Tool(
        name: "code.replace",
        description: """
            Replace code patterns using AST matching. Preserves matched content via meta-variables.

            IMPORTANT: dryRun=true (default) only previews changes. Set dryRun=false to apply.

            Examples:
            - Pattern: "print($MSG)" → Replacement: "logger.debug($MSG)"
            - Pattern: "var $NAME = $VALUE" → Replacement: "let $NAME = $VALUE"
            """,
        inputSchema: InputSchema(
            properties: [
                "pattern": Property(
                    type: "string",
                    description: "AST pattern with meta-variables"
                ),
                "replacement": Property(
                    type: "string",
                    description: "Replacement template; reuse $NAME / $$$ARGS captures"
                ),
                "path": Property(
                    type: "string",
                    description: "File or directory to rewrite, resolved under the workspace root (default: root). Paths resolving outside the root are rejected."
                ),
                "language": Property(
                    type: "string",
                    description: "Language hint (swift, python, javascript, …)"
                ),
                "dryRun": Property(
                    type: "boolean",
                    description: "true (default) = preview only; false = write changes to disk"
                ),
            ],
            required: ["pattern", "replacement"]
        )
    )

    static let all: [Tool] = [.search, .replacement]
}

// MARK: - Typed arguments

struct CodeSearchArguments: Decodable, Sendable {
    let pattern: String
    let path: String?
    let language: String?
}

struct CodeReplaceArguments: Decodable, Sendable {
    let pattern: String
    let replacement: String
    let path: String?
    let language: String?
    let dryRun: Bool?

    /// Explicit opt-in: only `dryRun: false` writes to disk.
    var appliesToDisk: Bool { dryRun == false }
}

// MARK: - Presentation (pure)

func formatSearchMatches(_ matches: [ASTGrepMatch]) -> String {
    guard !matches.isEmpty else { return "No matches found." }
    return (["Found \(matches.count) match(es):", ""]
        + matches.flatMap { match -> [String] in
            ["\(match.file):\(match.displayLine): \(match.text)"]
                + (match.captureSummary.isEmpty ? [] : ["  ↳ \(match.captureSummary)"])
        }).joined(separator: "\n")
}

func formatReplacementPreview(_ matches: [ASTGrepMatch], applied: Bool) -> String {
    guard !matches.isEmpty else { return "No matches found — nothing to replace." }

    let mode = applied ? "APPLIED" : "DRY RUN"
    var lines = ["\(mode): \(matches.count) replacement(s)", ""]
    for match in matches {
        guard let replacement = match.replacement else { continue }
        lines += [
            "\(match.file):\(match.displayLine):",
            "  - \(match.text)",
            "  + \(replacement)",
        ]
    }
    if !applied { lines += ["", "Preview only. Set dryRun=false to apply."] }
    return lines.joined(separator: "\n")
}
