import Foundation
import SwiftUI
import XCTest
@testable import AndromedaUI

/// Holds `DesignToken` to the `colors:` map in DESIGN.md at the repo root.
///
/// This package can't import `AndromedaBrand`, so its token values are a second copy.
/// These tests make that copy safe: every case must exist in DESIGN.md under its
/// `rawValue` with exactly its `hex`. The root package's `DesignTokenParityTests`
/// holds DESIGN.md to `web/app/globals.css`, closing the chain web → spec → SwiftUI.
final class DesignTokenParityTests: XCTestCase {
    /// Every token matches DESIGN.md by name and value.
    func testTokensMatchDesignSpec() throws {
        let spec = try DesignSpecColors.load()
        for token in DesignToken.allCases {
            let specHex = try XCTUnwrap(
                spec[token.rawValue],
                "DesignToken.\(token) has no `\(token.rawValue)` colour in DESIGN.md"
            )
            XCTAssertEqual(
                token.hexString, specHex,
                "DesignToken.\(token) is \(token.hexString); DESIGN.md `\(token.rawValue)` is \(specHex)"
            )
        }
    }

    /// Every dark-theme colour in DESIGN.md is available as a token, so a new token
    /// added to the system can't be silently missing from SwiftUI. `light-*` entries
    /// are web-only except the ones this package names explicitly.
    func testEveryDarkSpecColorIsAToken() throws {
        let spec = try DesignSpecColors.load()
        let tokenNames = Set(DesignToken.allCases.map(\.rawValue))
        let missing = spec.keys.filter { !$0.hasPrefix("light-") && !tokenNames.contains($0) }
        XCTAssertTrue(missing.isEmpty, "DESIGN.md colours with no DesignToken case: \(missing.sorted())")
    }

    /// The legacy `Color.andromeda*` names are backed by tokens — guards against a
    /// future edit reintroducing a literal for one of them.
    func testLegacyNamesResolveToTokens() {
        let pairs: [(Color, DesignToken)] = [
            (.andromedaVoid, .background), (.andromedaPanel, .card), (.andromedaTeal, .primary),
            (.andromedaGlow, .glow), (.andromedaLive, .signal), (.andromedaMuted, .mutedForeground),
            (.andromedaAmber, .partial), (.andromedaDim, .spec), (.andromedaInk, .foreground),
        ]
        for (legacy, token) in pairs {
            XCTAssertEqual(legacy, token.color, "legacy colour no longer resolves to `\(token.rawValue)`")
        }
    }

    /// The parser actually found the spec — an empty map would pass the other tests' loops.
    func testSpecParsed() throws {
        let spec = try DesignSpecColors.load()
        XCTAssertGreaterThanOrEqual(spec.count, 40, "parsed only \(spec.count) colours from DESIGN.md")
        XCTAssertEqual(spec["primary"], "#1DE4DB")
    }
}

private extension DesignToken {
    /// Uppercase `#RRGGBB`, the form DESIGN.md uses.
    var hexString: String { String(format: "#%06X", hex) }
}

/// DESIGN.md must open with YAML front matter; anything else fails the suite.
private struct MalformedSpec: Error, CustomStringConvertible {
    let path: String
    var description: String { "DESIGN.md has no YAML front matter at \(path)" }
}

/// The `colors:` map from DESIGN.md's YAML front matter.
private enum DesignSpecColors {
    /// DESIGN.md is at the repo root, five path components up from this file:
    /// `Packages/AndromedaUI/Tests/AndromedaUITests/<this file>`.
    static var url: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // AndromedaUITests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // AndromedaUI
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("DESIGN.md")
    }

    /// Reads `  name: "#RRGGBB"` entries under `colors:`; comment lines are skipped and
    /// values uppercased so hex case never causes a false failure.
    static func load() throws -> [String: String] {
        let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: .newlines)
        guard lines.first == "---" else {
            throw MalformedSpec(path: url.path)
        }
        var colors: [String: String] = [:]
        var inColors = false
        for line in lines.dropFirst() {
            if line == "---" { break }
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
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
