/**
 * 🌀 AndromedaASCII — the Andromeda trefoil and wordmark, rendered for terminals.
 *
 * The trefoil art is a density trace of the shipped app icon
 * (`web/public/andromeda-icon.png`): one petal rising, two petals splayed, a bright
 * core. Character density maps to the logo's glow, so `TerminalPaint` can shade
 * `.:-` as halo, `=+*` as accent, and `#%@` as the electric-cyan core.
 *
 * Sizes exist so the mark never gets clipped: `.full` for start-up banners in a
 * real terminal, `.compact` for inline chrome, `.wordmark` for the type lockup.
 */

import Foundation

public enum AndromedaASCII {
    public enum MarkSize: Sendable, CaseIterable {
        /// 46 columns — start-up banner in an 80-column terminal.
        case full
        /// 22 columns — inline / narrow chrome.
        case compact
    }

    /// The trefoil, as lines without trailing whitespace.
    public static func mark(_ size: MarkSize = .full) -> [String] {
        switch size {
        case .full: return fullMark
        case .compact: return compactMark
        }
    }

    private static let fullMark: [String] = [
        "                      .=-=*.",
        "                    .=-   ++",
        "                   -+     .%",
        "                  ==       %.",
        "                 .*   .*@%.@.",
        "                 #-  .%= -*+#",
        "                .@.==%:  .% @+",
        "                *@ #@%   *# -@=",
        "               :@* .%@:  @=  =@+",
        "              .%@:   +@#+#@*: :%%.",
        "              #@=     -@@@@@@#: +@-",
        "            .%@=       *@@@@@@+. .#*",
        "           :@%:  =+*#: +@@@@@@:    =#",
        "          +@+   *@@@@. %@@@@#.      ++",
        "        .%*.  .-@@@@--%@@@@-         %",
        "       .%:     .=+**@@@@@@@-         %",
        "       =*  .:  .-*@@%*+-::-=+#*=.  -*+",
        "        -+*****+=:            :-=+++:",
    ]

    private static let compactMark: [String] = [
        "          -:+:",
        "        :-  :--",
        "        +  =++*",
        "       :*#+ *=+",
        "       #- **%==*",
        "      #= : %@@* +-",
        "    -*:-@@-@@*   +",
        "   -=  -#%%##=:  =:",
        "    -===:     :--:",
    ]

    /// The `Andromeda` type lockup, machine-truth mono block form.
    public static let wordmark: [String] = {
        let block = #"""
     _                   _                                        _
    / \     _ __      __| | _ __    ___   _ __ ___     ___     __| |  __ _
   / _ \   | '_ \    / _` || '__|  / _ \ | '_ ` _ \   / _ \   / _` | / _` |
  / ___ \  | | | |  | (_| || |    | (_) || | | | | | |  __/  | (_| || (_| |
 /_/   \_\ |_| |_|   \__,_||_|     \___/ |_| |_| |_|  \___|   \__,_| \__,_|
"""#
        return block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }()

    /// Letter-spaced wordmark, the terminal echo of the web `tracking-widest` eyebrow.
    public static let spacedWordmark = "A N D R O M E D A"

    /// Widest line in a given mark, for centring and rule widths.
    public static func width(of lines: [String]) -> Int {
        lines.reduce(0) { max($0, $1.count) }
    }
}
