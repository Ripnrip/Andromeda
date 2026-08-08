/**
 * Andromeda ASCII trefoil — the terminal form of the mark.
 *
 * Byte-identical to `Sources/AndromedaBrand/AndromedaASCII.swift`. The Swift
 * module is the runtime source of truth for the TUI; this copy exists so the
 * design-system page can document the same art the terminal ships. If you change
 * one, change the other — `AndromedaBrandTests` guards the Swift side.
 */

export const FULL_MARK = [
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

export const COMPACT_MARK = [
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

export const WORDMARK = [
  "     _                   _                                        _",
  "    / \\     _ __      __| | _ __    ___   _ __ ___     ___     __| |  __ _",
  "   / _ \\   | '_ \\    / _` || '__|  / _ \\ | '_ ` _ \\   / _ \\   / _` | / _` |",
  "  / ___ \\  | | | |  | (_| || |    | (_) || | | | | | |  __/  | (_| || (_| |",
  " /_/   \\_\\ |_| |_|   \\__,_||_|     \\___/ |_| |_| |_|  \\___|   \\__,_| \\__,_|",
]

export type Shade = "halo" | "mid" | "core" | "void"

/** Density → glow shade. Mirrors `AndromedaChrome.paintedMark`. */
export function shadeFor(character: string): Shade {
  if (".:-".includes(character)) return "halo"
  if ("=+*".includes(character)) return "mid"
  if ("#%@".includes(character)) return "core"
  return "void"
}

export const SHADE_CLASS: Record<Shade, string> = {
  halo: "text-accent",
  mid: "text-shipped",
  core: "text-primary",
  void: "text-transparent",
}
