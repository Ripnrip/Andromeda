@testable import AndromedaOrchestrator
import Foundation
import Testing

/// Holds the console's `DesignToken` copy to the `colors:` map in DESIGN.md.
///
/// This package is standalone, so its token values are a copy. Every case must
/// exist in DESIGN.md under its `rawValue` (dark) and `light-<rawValue>` (light)
/// with exactly those values. The root package's parity tests hold DESIGN.md to
/// `web/app/globals.css`, so the console stays on the website's palette.
@Suite("Design token parity")
struct DesignTokenParityTests {
    /// Dark values match DESIGN.md's dark tokens by name.
    @Test("dark tokens match DESIGN.md")
    func darkTokensMatchSpec() throws {
        let spec = try DesignSpecColors.load()
        for token in DesignToken.allCases {
            let specHex = try #require(spec[token.rawValue], "DESIGN.md has no colour `\(token.rawValue)`")
            #expect(hexString(token.dark) == specHex, "DesignToken.\(token).dark is \(hexString(token.dark)); DESIGN.md `\(token.rawValue)` is \(specHex)")
        }
    }

    /// Light values match DESIGN.md's `light-*` tokens.
    @Test("light tokens match DESIGN.md")
    func lightTokensMatchSpec() throws {
        let spec = try DesignSpecColors.load()
        for token in DesignToken.allCases {
            let key = "light-" + token.rawValue
            let specHex = try #require(spec[key], "DESIGN.md has no colour `\(key)`")
            #expect(hexString(token.light) == specHex, "DesignToken.\(token).light is \(hexString(token.light)); DESIGN.md `\(key)` is \(specHex)")
        }
    }

    /// The parser actually found the spec, so the loops above can't pass vacuously.
    @Test("DESIGN.md parsed")
    func specParsed() throws {
        let spec = try DesignSpecColors.load()
        #expect(spec.count >= 40, "parsed only \(spec.count) colours from DESIGN.md")
        #expect(spec["primary"] == "#1DE4DB")
    }
}

/// Uppercase `#RRGGBB`, the form DESIGN.md uses.
private func hexString(_ value: UInt32) -> String {
    String(format: "#%06X", value)
}

/// DESIGN.md must open with YAML front matter; anything else fails the suite.
private struct MalformedSpec: Error, CustomStringConvertible {
    let path: String
    var description: String {
        "DESIGN.md has no YAML front matter at \(path)"
    }
}

/// The `colors:` map from DESIGN.md's YAML front matter.
private enum DesignSpecColors {
    /// DESIGN.md is at the repo root, five path components up from this file:
    /// `Packages/AndromedaOrchestrator/Tests/AndromedaOrchestratorTests/<this file>`.
    static var url: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // AndromedaOrchestratorTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // AndromedaOrchestrator
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("DESIGN.md")
    }

    /// Reads `  name: "#RRGGBB"` entries under `colors:`; comment and blank lines are
    /// skipped and values uppercased so hex case never causes a false failure.
    static func load() throws -> [String: String] {
        let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: .newlines)
        guard lines.first == "---" else {
            throw MalformedSpec(path: url.path)
        }
        var colors: [String: String] = [:]
        var inColors = false
        for line in lines.dropFirst() {
            if line == "---" {
                break
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            }
            if !line.hasPrefix(" ") {
                inColors = line.hasPrefix("colors:")
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard inColors, !trimmed.hasPrefix("#"), let colon = trimmed.firstIndex(of: ":") else { continue }
            let value = trimmed[trimmed.index(after: colon)...]
                .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                .uppercased()
            colors[String(trimmed[..<colon])] = value
        }
        return colors
    }
}
