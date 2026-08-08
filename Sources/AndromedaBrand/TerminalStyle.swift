/**
 * 🖥️ TerminalStyle — capability-aware ANSI renderer for the Andromeda TUI.
 *
 * Every terminal surface (andromeda, andromeda-runtime, future TUI panels) paints
 * through this type so brand colour is applied once, honestly, and degrades:
 * truecolor → 256 colour → plain text. Honours `NO_COLOR`, `TERM=dumb`, pipes,
 * and `FORCE_COLOR` / `CLICOLOR_FORCE`.
 */

import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct TerminalStyle: Sendable {
    public enum ColorMode: Sendable, Equatable {
        /// No escape sequences at all — pipes, `NO_COLOR`, dumb terminals.
        case plain
        /// xterm-256 cube.
        case ansi256
        /// 24-bit `38;2;r;g;b`.
        case truecolor
    }

    public let colorMode: ColorMode
    /// Whether box-drawing / dot glyphs are safe. False falls back to pure ASCII.
    public let unicodeAllowed: Bool
    /// Usable width for rules and banners.
    public let width: Int

    public init(colorMode: ColorMode, unicodeAllowed: Bool, width: Int = 72) {
        self.colorMode = colorMode
        self.unicodeAllowed = unicodeAllowed
        self.width = max(32, width)
    }

    /// Plain, colourless style — the safe default for logs and tests.
    public static let plain = TerminalStyle(colorMode: .plain, unicodeAllowed: false)

    // MARK: - Detection

    /// Resolve the style from the environment. Pure: pass `environment`/`isTTY` in tests.
    public static func detect(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isTTY: Bool = TerminalStyle.standardOutputIsTTY
    ) -> TerminalStyle {
        let term = environment["TERM"]?.lowercased() ?? ""

        func isTruthy(_ name: String) -> Bool {
            guard let value = environment[name] else { return false }
            return !value.isEmpty && value != "0"
        }
        let forced = isTruthy("FORCE_COLOR") || isTruthy("CLICOLOR_FORCE")
        let suppressed = !isTTY || environment["CI"] != nil

        // NO_COLOR is absolute: https://no-color.org
        let disabled = environment["NO_COLOR"] != nil
            || term == "dumb"
            || (suppressed && !forced)

        let colorMode: ColorMode
        if disabled {
            colorMode = .plain
        } else if let colorTerm = environment["COLORTERM"]?.lowercased(),
                  colorTerm.contains("truecolor") || colorTerm.contains("24bit")
        {
            colorMode = .truecolor
        } else if term.contains("256") || term.contains("kitty") || term.contains("alacritty") {
            colorMode = .ansi256
        } else if term.isEmpty {
            // FORCE_COLOR / CLICOLOR_FORCE already cleared `disabled` above — empty TERM
            // in CI/containers must still produce ANSI when colour is forced, not plain.
            colorMode = forced ? .ansi256 : .plain
        } else {
            colorMode = .ansi256
        }

        // Color capability must not imply Unicode: LANG=C + color TERM should keep ASCII
        // fallbacks. Unset locale vars default to UTF-8 (modern shells); dumb TERM never.
        let unicodeAllowed = term != "dumb" && localeAllowsUnicode(environment)

        return TerminalStyle(
            colorMode: colorMode,
            unicodeAllowed: unicodeAllowed,
            width: environment["COLUMNS"].flatMap { Int($0) } ?? 72
        )
    }

    /// True when the process locale can emit UTF-8 glyphs safely.
    ///
    /// Checks `LC_ALL`, then `LC_CTYPE`, then `LANG`. If none are set, assume UTF-8.
    /// Explicit ASCII locales (`C`, `POSIX`, `en_US.ISO8859-1`, …) return false.
    private static func localeAllowsUnicode(_ environment: [String: String]) -> Bool {
        let keys = ["LC_ALL", "LC_CTYPE", "LANG"]
        let values = keys.compactMap { environment[$0] }.filter { !$0.isEmpty }
        guard let primary = values.first else { return true }
        let upper = primary.uppercased()
        if upper == "C" || upper == "POSIX" { return false }
        return upper.contains("UTF-8") || upper.contains("UTF8")
    }

    public static var standardOutputIsTTY: Bool {
        #if canImport(Darwin) || canImport(Glibc)
        return isatty(1) == 1
        #else
        return false
        #endif
    }

    // MARK: - Painting

    private static let reset = "\u{001B}[0m"

    /// Wrap `text` in brand colour and attributes, or return it untouched in plain mode.
    public func paint(
        _ text: String,
        _ color: BrandColor? = nil,
        bold: Bool = false,
        dim: Bool = false,
        italic: Bool = false
    ) -> String {
        guard colorMode != .plain else { return text }
        var codes: [String] = []
        if bold { codes.append("1") }
        if dim { codes.append("2") }
        if italic { codes.append("3") }
        if let color {
            switch colorMode {
            case .truecolor:
                codes.append("38;2;\(color.red);\(color.green);\(color.blue)")
            case .ansi256:
                codes.append("38;5;\(color.ansi256)")
            case .plain:
                break
            }
        }
        guard !codes.isEmpty else { return text }
        return "\u{001B}[" + codes.joined(separator: ";") + "m" + text + Self.reset
    }

    /// Pick the Unicode glyph when safe, otherwise the ASCII stand-in.
    public func glyph(_ unicode: String, ascii: String) -> String {
        unicodeAllowed ? unicode : ascii
    }
}
