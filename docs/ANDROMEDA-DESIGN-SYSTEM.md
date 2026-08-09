# Andromeda Design System — one visual system, every surface

> **Audience:** any agent or human touching Andromeda UI — website, terminal, macOS.
> **Rule:** there is exactly one Andromeda theme. Never invent a second one.
> **Tickets:** BIN-229 (roll-out), BIN-230 (app UI), BIN-231 (terminal TUI), BIN-232 (shared patterns).

## Sources of truth

| Layer | Source of truth | Consumers |
|-------|-----------------|-----------|
| Colour, radius | `web/app/globals.css` (`oklch` tokens) → transcribed to sRGB in `Sources/AndromedaBrand/AndromedaPalette.swift` | web, TUI, SwiftUI |
| Trefoil / wordmark ASCII | `Sources/AndromedaBrand/AndromedaASCII.swift` (mirrored for docs in `web/lib/ascii-mark.ts`) | TUI, design page |
| Terminal chrome | `Sources/AndromedaBrand/AndromedaChrome.swift` | `andromeda`, `andromeda-runtime` |
| SwiftUI tokens | `Sources/AndromedaBrand/AndromedaTheme+SwiftUI.swift` | Home, HUD, menu bar, command center |
| SwiftUI control-plane UI | `Packages/AndromedaUI` (BIN-270+) — palette aliases, motion, floating bar, sections | macOS control plane surfaces |
| Rendered spec | `/design` on the website | everyone |

`AndromedaBrandTests` asserts hex parity with the web tokens, so drift fails CI
rather than shipping two themes.

## Identity

Deep-space obsidian teal. Dark-only, near-black blue-green ground, one electric
cyan accent, editorial serif for emotion, monospace for machine truth. Calm and
instrument-like, never neon cyberpunk. No purple, no gradients as primary
elements, no emoji-as-icon, no decorative blobs.

## Palette

| Token | hex | Role |
|-------|-----|------|
| `background` | `#040F12` | obsidian ground |
| `foreground` | `#E6F1F2` | primary text |
| `card` / `popover` | `#081619` / `#071416` | panel / floating ground |
| `muted` / `muted-foreground` | `#142224` / `#8B9C9E` | inert fill / secondary text |
| `border` / `input` | `#203839` / `#1A2D2F` | hairline / field stroke |
| `primary` (`ring`, `shipped`) | `#1DE4DB` | electric cyan — the only hue that leads |
| `accent` | `#00A8AA` | supporting teal, trefoil halo |
| `signal` | `#49DE78` | healthy / positive delta |
| `partial` | `#E5C057` | in progress / warning / `CAVEAT` |
| `spec` | `#79898F` | specified only / inert |

`--radius` is `0.875rem` on web and 14 pt natively.

## Typography

- **Space Grotesk** — body and UI (`font-sans`).
- **Instrument Serif** — display headlines, italic emphasis.
- **JetBrains Mono** — machine truth only: capability IDs, eyebrow labels,
  status chips, paths, log lines, `CAVEAT` callouts. The whole TUI is this voice.

## Terminal (TUI)

`swift run andromeda brand` prints the entire terminal vocabulary. Everything
routes through `AndromedaChrome`, never raw `print` with hand-rolled escapes.

- **Trefoil** — `AndromedaASCII.mark(.full)` (38 cols) and `.compact` (19 cols),
  a density trace of the shipped app icon. `AndromedaChrome.paintedMark` shades
  density as the logo's glow: `.:-` → accent halo, `=+*` → cyan mid,
  `#%@` → electric-cyan core.
- **Wordmark** — `AndromedaASCII.wordmark` (74 cols) for start-up banners;
  `spacedWordmark` (`A N D R O M E D A`) for compact chrome.
- **Eyebrow** — `AndromedaChrome.eyebrow("autocache gateway")` letter-spaces
  uppercase mono, the terminal echo of `tracking-widest text-primary`.
- **Status chip** — coloured dot **plus** its mono word. Vocabulary:
  `SHIPPED / PARTIAL / SPECIFIED` for roadmap surfaces,
  `HEALTHY / DEGRADED / OFFLINE` for runtime. Status is never colour-only.
- **Field row** — mono muted key padded to a stable column, foreground value.
- **CAVEAT callout** — amber lead-in for honest disclaimers; use it instead of
  faking data or greenwashing a pillar.
- **Rule** — hairline in `border`, the `border-t` band separator.

### Colour capability and degradation

`TerminalStyle.detect()` resolves once per process:

1. `NO_COLOR` (any value), `TERM=dumb`, CI, or a non-TTY stdout → **plain text**,
   zero escape sequences.
2. `COLORTERM=truecolor|24bit` → **24-bit** `38;2;r;g;b`.
3. otherwise → **xterm-256** nearest-cube fallback (including when `TERM` is
   empty but colour is forced).
4. `FORCE_COLOR` / `CLICOLOR_FORCE` override the non-TTY and CI suppression —
   including containers that set force flags with no `TERM`.

Unicode glyphs (`●`, `─`, `◈`) fall back to ASCII (`*`, `-`, `<>`) unless the
locale is UTF-8 capable (`LC_ALL` / `LC_CTYPE` / `LANG`). Color-capable
terminals under `LANG=C` stay ASCII. Unset locale vars default to UTF-8; dumb
terminals never get Unicode. Banners print to **stdout**, never through the log
stream, so structured log lines stay machine-parseable.

## macOS surfaces

`AndromedaTheme` exposes the same tokens as SwiftUI `Color`s, plus
`AndromedaStatusChip` (dot + mono word), `AndromedaTheme.mono(_:)` and
`AndromedaTheme.display(_:)`. Menu bar popovers and the floating command center
use `popover` ground, 14 pt radius, hairline `border` stroke, mono row labels and
a cyan primary action. Respect Reduce Motion and Increase Contrast; animation
stays ≤ 200 ms, opacity/scale only.

## Honesty rules (inherited, non-negotiable)

- Status is never communicated by colour alone.
- Stubbed features get a `CAVEAT`, not fabricated data.
- Client-facing surfaces show stable capability IDs only — never Linear /
  Multica / provider brand names / raw env key names.
- Secrets render as stable proxy IDs, never values.

## Open work

- **BIN-270 Gate 0 (this lane):** `Packages/AndromedaUI` vendored and compiling as a
  nested Swift package. Snapshot PNG baselines are still unrecorded — suites skip
  until a macOS record pass lands in the verification follow-up.
- **PR split (do not land as one blob):**
  1. Gate 0 — compile `AndromedaUI` standalone (`swift test` in `Packages/AndromedaUI`)
  2. Port tokens — converge `AndromedaUI` Color aliases onto `AndromedaBrand` / web OKLCH
  3. Floating control bar — wire `FloatingBarPanel` into the app shell
  4. Control-plane sections — Memory / Search / Settings / capability modules as reusable screens
  5. TUI parity — ASCII mark + teal/void styling share the same token set
  6. Verification — record snapshots + a11y coverage without snapshot sprawl
- **BIN-230 / BIN-232:** `AndromedaHomeCore` and `AndromedaHUDCore` still use
  system colours (`.cyan`, `.green`, `windowBackgroundColor`). Migrating them to
  `AndromedaTheme` changes recorded SwiftUI snapshots, so it needs a macOS
  checkout to re-record `Tests/AndromedaHomeTests/__Snapshots__` and
  `Tests/AndromedaHUDTests/__Snapshots__` in the same change.
- `docs/demo/doctor-checklist.txt` is a pre-brand transcript; re-capture it after
  the next doctor run on a host.
