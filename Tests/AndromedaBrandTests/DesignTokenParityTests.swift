import Foundation
import Testing
@testable import AndromedaBrand

/// Parity gate for the shared design system.
///
/// Three artefacts describe the same palette:
/// - `web/app/globals.css` — authored in oklch; the source the website renders.
/// - `DESIGN.md` — the agent-facing spec (Google Labs DESIGN.md format), hex values.
/// - `AndromedaPalette` — the sRGB tokens every native and terminal surface reads.
///
/// These tests convert each oklch token to sRGB with the reference OKLab → linear
/// sRGB matrices, then require `DESIGN.md` and `AndromedaPalette` to match the
/// conversion exactly. A token changed in one place but not the others fails CI.
@Suite("Design token parity")
struct DesignTokenParityTests {
    /// Every `.dark` token in globals.css that is a native palette entry must match
    /// `AndromedaPalette` byte-for-byte (native surfaces are dark-only).
    @Test("AndromedaPalette matches the web dark theme")
    func paletteMatchesWebDarkTheme() throws {
        let web = try WebTokens.load()
        for token in AndromedaPalette.all {
            let webHex = try #require(
                web.dark[token.name],
                "AndromedaPalette.\(token.name) has no `--\(token.name)` in globals.css .dark"
            )
            #expect(
                token.color.hex == webHex,
                "AndromedaPalette.\(token.name) is \(token.color.hex); globals.css .dark converts to \(webHex)"
            )
        }
    }

    /// DESIGN.md must list every web token, dark under its own name and light under
    /// a `light-` prefix, with the exact converted value.
    @Test("DESIGN.md colours match globals.css for both themes")
    func designSpecMatchesWeb() throws {
        let web = try WebTokens.load()
        let spec = try DesignSpec.loadColors()

        for (name, webHex) in web.dark {
            let specHex = try #require(spec[name], "DESIGN.md is missing colour `\(name)`")
            #expect(specHex == webHex, "DESIGN.md `\(name)` is \(specHex); globals.css .dark converts to \(webHex)")
        }
        for (name, webHex) in web.light {
            let key = "light-" + name
            let specHex = try #require(spec[key], "DESIGN.md is missing colour `\(key)`")
            #expect(specHex == webHex, "DESIGN.md `\(key)` is \(specHex); globals.css :root converts to \(webHex)")
        }
    }

    /// DESIGN.md may not invent colours the website doesn't define — the spec says
    /// "nothing else", so the tests hold it to that.
    @Test("DESIGN.md defines no colours outside the web tokens")
    func designSpecHasNoExtraColors() throws {
        let web = try WebTokens.load()
        let known = Set(web.dark.keys).union(web.light.keys.map { "light-" + $0 })
        let extra = try Set(DesignSpec.loadColors().keys).subtracting(known)
        #expect(extra.isEmpty, "DESIGN.md colours with no globals.css source: \(extra.sorted())")
    }

    /// Guards the converter itself against a reference value, so a broken parser
    /// can't make the parity tests pass vacuously.
    @Test("oklch conversion matches a known reference")
    func conversionReference() throws {
        #expect(OKLCH(lightness: 0.83, chroma: 0.14, hue: 190).srgbHex == "#1DE4DB")
        #expect(OKLCH(lightness: 1, chroma: 0, hue: 0).srgbHex == "#FFFFFF")
        let web = try WebTokens.load()
        #expect(web.dark.count >= 20, "parsed only \(web.dark.count) dark tokens from globals.css")
        #expect(web.light.count >= 20, "parsed only \(web.light.count) light tokens from globals.css")
    }
}

// MARK: - Repository files

/// Resolves the package root from this test source location, independent of the
/// caller's working directory (same approach as RepositoryPolicyTests).
private func repositoryRootURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// Reads a repo-relative UTF-8 text file.
private func readRepositoryFile(_ relativePath: String) throws -> String {
    try String(contentsOf: repositoryRootURL().appendingPathComponent(relativePath), encoding: .utf8)
}

// MARK: - oklch → sRGB

/// An oklch colour as authored in globals.css.
private struct OKLCH {
    let lightness: Double
    let chroma: Double
    let hue: Double

    /// Uppercase `#RRGGBB` after OKLab → linear sRGB → gamma encoding, clamped to
    /// gamut and rounded half away from zero (matching `BrandColor` transcription).
    var srgbHex: String {
        let radians = hue * .pi / 180
        let a = chroma * cos(radians)
        let b = chroma * sin(radians)

        let lPrime = lightness + 0.3963377774 * a + 0.2158037573 * b
        let mPrime = lightness - 0.1055613458 * a - 0.0638541728 * b
        let sPrime = lightness - 0.0894841775 * a - 1.2914855480 * b
        let l = lPrime * lPrime * lPrime
        let m = mPrime * mPrime * mPrime
        let s = sPrime * sPrime * sPrime

        let linear = [
            4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
        ]
        let bytes = linear.map { channel -> Int in
            let clamped = min(max(channel, 0), 1)
            let encoded = clamped <= 0.0031308 ? 12.92 * clamped : 1.055 * pow(clamped, 1 / 2.4) - 0.055
            return Int((encoded * 255).rounded())
        }
        return String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2])
    }
}

// MARK: - globals.css

/// The oklch custom properties declared in globals.css, converted to sRGB hex.
private struct WebTokens {
    /// `.dark { … }` — keyed by property name without the leading `--`.
    let dark: [String: String]
    /// `:root { … }` (the light theme).
    let light: [String: String]

    /// Parses both theme blocks out of `web/app/globals.css`.
    static func load() throws -> WebTokens {
        let css = try readRepositoryFile("web/app/globals.css")
        return WebTokens(
            dark: try parseBlock(named: ".dark", in: css),
            light: try parseBlock(named: ":root", in: css)
        )
    }

    /// Extracts `--name: oklch(L C h);` declarations from the first rule whose
    /// selector line is exactly `<selector> {`. Non-oklch properties are ignored.
    private static func parseBlock(named selector: String, in css: String) throws -> [String: String] {
        let lines = css.components(separatedBy: .newlines)
        let start = try #require(
            lines.firstIndex { $0.trimmingCharacters(in: .whitespaces) == selector + " {" },
            "globals.css has no `\(selector) {` block"
        )

        var tokens: [String: String] = [:]
        for line in lines[(start + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("}") { break }
            guard trimmed.hasPrefix("--"),
                  let colon = trimmed.firstIndex(of: ":"),
                  let open = trimmed.range(of: "oklch("),
                  let close = trimmed.range(of: ")", range: open.upperBound..<trimmed.endIndex)
            else { continue }

            let name = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<colon])
            let components = trimmed[open.upperBound..<close.lowerBound]
                .split(whereSeparator: \.isWhitespace)
                .compactMap { Double($0) }
            guard components.count == 3 else { continue }
            tokens[name] = OKLCH(lightness: components[0], chroma: components[1], hue: components[2]).srgbHex
        }
        return tokens
    }
}

// MARK: - DESIGN.md

/// The `colors:` map from DESIGN.md's YAML front matter.
private enum DesignSpec {
    /// Reads `  name: "#RRGGBB"` entries under `colors:`; comments are skipped and
    /// values are uppercased so hex case never causes a false failure.
    static func loadColors() throws -> [String: String] {
        let lines = try readRepositoryFile("DESIGN.md").components(separatedBy: .newlines)
        #expect(lines.first == "---", "DESIGN.md must open with YAML front matter")

        var colors: [String: String] = [:]
        var inColors = false
        for line in lines.dropFirst() {
            if line == "---" { break }
            if !line.hasPrefix(" ") {
                inColors = line.hasPrefix("colors:")
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard inColors, !trimmed.hasPrefix("#"), let colon = trimmed.firstIndex(of: ":") else { continue }
            let name = String(trimmed[..<colon])
            let value = trimmed[trimmed.index(after: colon)...]
                .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                .uppercased()
            colors[name] = value
        }
        return colors
    }
}
