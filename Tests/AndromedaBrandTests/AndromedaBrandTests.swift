import Foundation
import Testing
@testable import AndromedaBrand

@Suite("AndromedaPalette")
struct AndromedaPaletteTests {
    @Test("tokens match the web design-system hex values")
    func hexParity() {
        // Parity with web/app/globals.css — if these drift, the surfaces drift.
        #expect(AndromedaPalette.background.hex == "#040F12")
        #expect(AndromedaPalette.foreground.hex == "#E6F1F2")
        #expect(AndromedaPalette.primary.hex == "#1DE4DB")
        #expect(AndromedaPalette.accent.hex == "#00A8AA")
        #expect(AndromedaPalette.border.hex == "#203839")
        #expect(AndromedaPalette.signal.hex == "#49DE78")
        #expect(AndromedaPalette.partial.hex == "#E5C057")
        #expect(AndromedaPalette.spec.hex == "#79898F")
    }

    @Test("palette stays disciplined and fully enumerated")
    func paletteDiscipline() {
        #expect(AndromedaPalette.all.count == 17)
        #expect(Set(AndromedaPalette.all.map(\.name)).count == AndromedaPalette.all.count)
        #expect(AndromedaPalette.shipped == AndromedaPalette.primary)
    }

    @Test("256-colour fallback stays inside the xterm cube")
    func ansi256Range() {
        for token in AndromedaPalette.all {
            #expect(token.color.ansi256 >= 16)
            #expect(token.color.ansi256 <= 231)
        }
    }
}

@Suite("TerminalStyle")
struct TerminalStyleTests {
    @Test("NO_COLOR wins over everything")
    func noColorHonoured() {
        let style = TerminalStyle.detect(
            environment: ["NO_COLOR": "1", "COLORTERM": "truecolor", "TERM": "xterm-256color"],
            isTTY: true
        )
        #expect(style.colorMode == .plain)
        #expect(style.paint("memory.recall", AndromedaPalette.primary) == "memory.recall")
    }

    @Test("pipes stay plain unless colour is forced")
    func pipesArePlain() {
        let piped = TerminalStyle.detect(environment: ["TERM": "xterm-256color"], isTTY: false)
        #expect(piped.colorMode == .plain)

        let forced = TerminalStyle.detect(
            environment: ["TERM": "xterm-256color", "FORCE_COLOR": "1"],
            isTTY: false
        )
        #expect(forced.colorMode == .ansi256)
    }

    @Test("FORCE_COLOR still paints ANSI when TERM is absent")
    func forceColorWithoutTerm() {
        // Codex P2: CI/containers often set FORCE_COLOR with no TERM; must not fall to .plain.
        let forced = TerminalStyle.detect(
            environment: ["FORCE_COLOR": "1", "CI": "1"],
            isTTY: false
        )
        #expect(forced.colorMode == .ansi256)

        let unforced = TerminalStyle.detect(environment: [:], isTTY: false)
        #expect(unforced.colorMode == .plain)
    }

    @Test("truecolor terminals get 24-bit sequences")
    func truecolorSequences() {
        let style = TerminalStyle.detect(
            environment: ["TERM": "xterm-256color", "COLORTERM": "truecolor", "LANG": "en_US.UTF-8"],
            isTTY: true
        )
        #expect(style.colorMode == .truecolor)
        let painted = style.paint("ok", AndromedaPalette.primary, bold: true)
        #expect(painted.contains("38;2;29;228;219"))
        #expect(painted.hasSuffix("\u{001B}[0m"))
    }

    @Test("dumb terminals get neither colour nor unicode glyphs")
    func dumbTerminal() {
        let style = TerminalStyle.detect(environment: ["TERM": "dumb"], isTTY: true)
        #expect(style.colorMode == .plain)
        #expect(style.glyph("●", ascii: "*") == "*")
    }

    @Test("ASCII locales keep ASCII glyph fallbacks even when colour is on")
    func unicodeGatedByLocale() {
        // Codex P2: color capability must not imply Unicode-safe output.
        let asciiLocale = TerminalStyle.detect(
            environment: ["TERM": "xterm-256color", "LANG": "C"],
            isTTY: true
        )
        #expect(asciiLocale.colorMode == .ansi256)
        #expect(asciiLocale.unicodeAllowed == false)
        #expect(asciiLocale.glyph("●", ascii: "*") == "*")

        let utf8 = TerminalStyle.detect(
            environment: ["TERM": "xterm-256color", "LANG": "en_US.UTF-8"],
            isTTY: true
        )
        #expect(utf8.unicodeAllowed == true)
        #expect(utf8.glyph("●", ascii: "*") == "●")
    }
}

@Suite("AndromedaASCII")
struct AndromedaASCIITests {
    @Test("marks fit their advertised terminal widths")
    func markWidths() {
        #expect(AndromedaASCII.width(of: AndromedaASCII.mark(.full)) <= 46)
        #expect(AndromedaASCII.width(of: AndromedaASCII.mark(.compact)) <= 22)
        #expect(AndromedaASCII.width(of: AndromedaASCII.wordmark) <= 80)
    }

    @Test("art is pure ASCII so any terminal can render the logo")
    func asciiOnly() {
        let lines = AndromedaASCII.mark(.full) + AndromedaASCII.mark(.compact) + AndromedaASCII.wordmark
        for line in lines {
            // Avoid `#expect(line.allSatisfy(\.isASCII))` — Swift Testing's macro
            // expansion treats key-path allSatisfy as a throwing call.
            let isASCII = line.unicodeScalars.allSatisfy(\.isASCII)
            #expect(isASCII)
        }
    }

    @Test("trefoil has a bright core and no blank frames")
    func trefoilShape() {
        let full = AndromedaASCII.mark(.full)
        #expect(full.count == 18)
        #expect(full.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        #expect(full.contains { $0.contains("@@@") })
    }
}

@Suite("AndromedaChrome")
struct AndromedaChromeTests {
    let plain = TerminalStyle.plain

    @Test("status is never colour-only — the word always ships")
    func statusAlwaysWorded() {
        for status in BrandStatus.allCases {
            let chip = AndromedaChrome.statusChip(status, style: plain)
            #expect(chip.contains(status.word))
        }
    }

    @Test("status colours map to the roadmap/runtime vocabulary")
    func statusColours() {
        #expect(BrandStatus.shipped.color == AndromedaPalette.shipped)
        #expect(BrandStatus.healthy.color == AndromedaPalette.signal)
        #expect(BrandStatus.partial.color == AndromedaPalette.partial)
        #expect(BrandStatus.degraded.color == AndromedaPalette.partial)
        #expect(BrandStatus.specified.color == AndromedaPalette.spec)
        #expect(BrandStatus.offline.color == AndromedaPalette.spec)
    }

    @Test("plain mode emits zero escape sequences")
    func plainModeIsClean() {
        let output = [
            AndromedaChrome.banner(
                surface: "autocache gateway",
                version: "0.1.0-autocache",
                tagline: "Anthropic prompt-cache proxy.",
                style: plain
            ),
            AndromedaChrome.eyebrow("capability curtain", style: plain),
            AndromedaChrome.rule(40, style: plain),
            AndromedaChrome.field("bind", "127.0.0.1:8080", style: plain),
            AndromedaChrome.caveat("Secrets broker is not shipped.", style: plain),
            AndromedaChrome.pill("observing", style: plain),
            AndromedaChrome.principles(["Local first.", "No silent sprawl."], style: plain),
        ].joined(separator: "\n")
        #expect(!output.contains("\u{001B}"))
    }

    @Test("eyebrow letter-spaces uppercase mono labels")
    func eyebrowTracking() {
        #expect(AndromedaChrome.eyebrow("mcp", style: plain) == "M C P")
    }

    @Test("banner carries mark, wordmark, surface and tagline")
    func bannerComposition() {
        let banner = AndromedaChrome.banner(
            surface: "runtime v2",
            version: nil,
            tagline: "Memory behind the curtain.",
            style: plain
        )
        #expect(banner.contains("@@@"))
        #expect(banner.contains("R U N T I M E   V 2"))
        #expect(banner.contains("Memory behind the curtain."))
        #expect(!banner.contains("v\n"))
    }

    @Test("compact banner swaps the wordmark for the spaced lockup")
    func compactBanner() {
        let banner = AndromedaChrome.banner(
            surface: "design system",
            version: "0.1.0",
            tagline: "One system.",
            style: plain,
            compact: true
        )
        #expect(banner.contains(AndromedaASCII.spacedWordmark))
        #expect(banner.contains("v0.1.0"))
    }

    @Test("painted mark shades density as the logo's glow")
    func paintedGlow() {
        let style = TerminalStyle(colorMode: .truecolor, unicodeAllowed: true)
        let painted = AndromedaChrome.paintedMark(.compact, style: style).joined(separator: "\n")
        // core = primary cyan, mid = shipped cyan, halo = accent teal
        #expect(painted.contains("38;2;29;228;219"))
        #expect(painted.contains("38;2;0;168;170"))
    }

    @Test("field rows pad keys to a stable mono column")
    func fieldAlignment() {
        let row = AndromedaChrome.field("bind", "127.0.0.1:8788", style: plain, keyWidth: 12)
        #expect(row == "bind        127.0.0.1:8788")
    }
}
