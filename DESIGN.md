---
version: alpha
name: Andromeda
description: >-
  Deep-space control plane. Obsidian teal ground, one electric-cyan accent, an
  honest status trio, editorial serif display over a grotesk UI and mono
  machine-truth. Shared by the website (web/), the macOS surfaces
  (AndromedaHome, AndromedaHUD) and the CLI/TUI (AndromedaChrome).
colors:
  # Dark — canonical. The site defaults to dark; native + TUI are dark-only.
  background: "#040F12"
  foreground: "#E6F1F2"
  card: "#081619"
  card-foreground: "#E6F1F2"
  popover: "#071416"
  popover-foreground: "#E6F1F2"
  primary: "#1DE4DB"
  primary-foreground: "#001114"
  accent: "#00A8AA"
  accent-foreground: "#F1FBFB"
  secondary: "#122225"
  secondary-foreground: "#DCE7E8"
  muted: "#142224"
  muted-foreground: "#8B9C9E"
  border: "#203839"
  input: "#1A2D2F"
  ring: "#1DE4DB"
  shipped: "#1DE4DB"
  signal: "#49DE78"
  partial: "#E5C057"
  spec: "#7A898F"
  # Light — web only. Same token names, `light-` prefix.
  light-background: "#F7FBFC"
  light-foreground: "#0F1D20"
  light-card: "#FFFFFF"
  light-card-foreground: "#0F1D20"
  light-popover: "#FFFFFF"
  light-popover-foreground: "#0F1D20"
  light-primary: "#008B8C"
  light-primary-foreground: "#F8FDFD"
  light-accent: "#007578"
  light-accent-foreground: "#F8FDFD"
  light-secondary: "#E5EDEE"
  light-secondary-foreground: "#1D2C2E"
  light-muted: "#E5EDEE"
  light-muted-foreground: "#4C5B5E"
  light-border: "#CFDADC"
  light-input: "#D5E0E2"
  light-ring: "#008B8C"
  light-shipped: "#00787A"
  light-signal: "#00792F"
  light-partial: "#996700"
  light-spec: "#687478"
typography:
  display:
    fontFamily: Instrument Serif
    fontSize: 3.75rem
    fontWeight: 400
    lineHeight: 1.02
    letterSpacing: -0.025em
  h1:
    fontFamily: Instrument Serif
    fontSize: 2.25rem
    fontWeight: 400
    lineHeight: 1.1
    letterSpacing: -0.025em
  h2:
    fontFamily: Space Grotesk
    fontSize: 1.5rem
    fontWeight: 600
    lineHeight: 1.3
  section-title:
    fontFamily: Instrument Serif
    fontSize: 1.875rem
    fontWeight: 400
    lineHeight: 1.2
    letterSpacing: -0.025em
  body:
    fontFamily: Space Grotesk
    fontSize: 1rem
    fontWeight: 400
    lineHeight: 1.625
  body-sm:
    fontFamily: Space Grotesk
    fontSize: 0.875rem
    fontWeight: 400
    lineHeight: 1.625
  eyebrow:
    fontFamily: JetBrains Mono
    fontSize: 0.75rem
    fontWeight: 500
    lineHeight: 1
    letterSpacing: 0.3em
  mono:
    fontFamily: JetBrains Mono
    fontSize: 0.875rem
    fontWeight: 400
    lineHeight: 1.5
  mono-caption:
    fontFamily: JetBrains Mono
    fontSize: 0.6875rem
    fontWeight: 600
    lineHeight: 1
    letterSpacing: 0.1em
rounded:
  sm: 10px
  md: 12px
  lg: 14px
  xl: 18px
  full: 9999px
spacing:
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 40px
  section: 56px
  gutter: 24px
  dotgrid: 22px
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.primary-foreground}"
    typography: "{typography.body}"
    rounded: "{rounded.md}"
    padding: 12px 20px
  button-secondary:
    backgroundColor: "{colors.card}"
    textColor: "{colors.foreground}"
    typography: "{typography.body}"
    rounded: "{rounded.md}"
    padding: 12px 20px
  card:
    backgroundColor: "{colors.card}"
    textColor: "{colors.card-foreground}"
    rounded: "{rounded.md}"
    padding: 24px
  capability-token:
    backgroundColor: "{colors.secondary}"
    textColor: "{colors.secondary-foreground}"
    typography: "{typography.mono-caption}"
    rounded: 6px
    padding: 6px 10px
  capability-chip:
    backgroundColor: "{colors.card}"
    textColor: "{colors.foreground}"
    typography: "{typography.mono-caption}"
    rounded: "{rounded.full}"
    padding: 6px 12px
  status-chip:
    typography: "{typography.mono-caption}"
    rounded: "{rounded.full}"
    padding: 3px 8px
  status-chip-shipped:
    textColor: "{colors.shipped}"
  status-chip-healthy:
    textColor: "{colors.signal}"
  status-chip-partial:
    textColor: "{colors.partial}"
  status-chip-spec:
    textColor: "{colors.spec}"
  eyebrow:
    textColor: "{colors.primary}"
    typography: "{typography.eyebrow}"
  popover:
    backgroundColor: "{colors.popover}"
    textColor: "{colors.popover-foreground}"
    rounded: "{rounded.md}"
    padding: 12px
  chip-hover:
    backgroundColor: "{colors.muted}"
    textColor: "{colors.foreground}"
  field-key:
    textColor: "{colors.muted-foreground}"
    typography: "{typography.mono}"
  hairline:
    backgroundColor: "{colors.border}"
    height: 1px
  text-input:
    backgroundColor: "{colors.input}"
    textColor: "{colors.foreground}"
    typography: "{typography.body}"
    rounded: "{rounded.md}"
    padding: 12px 16px
  focus-ring:
    backgroundColor: "{colors.ring}"
    width: 2px
  version-tag:
    backgroundColor: "{colors.background}"
    textColor: "{colors.accent}"
    typography: "{typography.mono-caption}"
---

## Overview

Andromeda is a local-first, Swift-native control plane: agents, jobs, tools, models, secrets, memory and fleet state behind one capability curtain. The visual language is derived from the logo — a glowing teal trefoil suspended in deep space above a lit horizon.

Three adjectives govern every surface: **calm, luminous, honest.** The ground is near-black obsidian teal; light comes from a single electric-cyan source; status is reported plainly and never decorated.

This file is the single source of truth for every Andromeda surface:

| Surface | Implementation | Reads tokens from |
|---|---|---|
| Website | `web/` (Next.js 15, Tailwind v4) | `web/app/globals.css` (`@theme inline` + `:root` / `.dark`) |
| macOS (Home, HUD, menu bar, floating command center) | SwiftUI | `Sources/AndromedaBrand/AndromedaTheme+SwiftUI.swift` |
| CLI / TUI | `AndromedaChrome`, `TerminalStyle` | `Sources/AndromedaBrand/AndromedaPalette.swift` |
| Living reference | `/design` route | live CSS variables |

Token names are identical across all three. If a value changes here, it changes in `globals.css` and `AndromedaPalette.swift` in the same commit. `Tests/AndromedaBrandTests/DesignTokenParityTests.swift` converts the oklch values in `globals.css` to sRGB and fails CI if this file or `AndromedaPalette` disagrees with them.

> **Known divergence (BIN-271).** `Packages/AndromedaUI` still carries a parallel SwiftUI palette (`Color.andromeda{Void, Panel, Teal, …}`) and its own `AndromedaTheme` enum, whose values differ from these tokens — its teal is `#34E8DC`, and its `accent` is a bright glow rather than the deep teal. New code should use `AndromedaBrand` (`AndromedaTheme` / `AndromedaPalette`). Converging AndromedaUI requires re-recording its snapshot baselines on the CI runner, so it is tracked separately.

## Colors

A five-role palette — **void ground, panel slate, hairline border, cyan glow, light foreground** — plus a status trio. Nothing else.

- **Background (#040F12):** obsidian teal ground. Every surface starts here.
- **Card (#081619) / Popover (#071416):** one step above the ground for panels, bars and floating surfaces. Depth comes from these steps, not from shadows.
- **Secondary (#122225) / Muted (#142224):** inert fills — chips, hover states, code tokens.
- **Border (#203839) / Input (#1A2D2F):** hairlines. Borders are 1px and quiet.
- **Foreground (#E6F1F2):** primary text. **Muted-foreground (#8B9C9E):** secondary text, metadata, field keys.
- **Primary (#1DE4DB):** electric cyan. The only saturated hue that leads. Used for primary actions, focus rings, eyebrows, the orbital pulse and glow. Never as a large fill behind body text.
- **Accent (#00A8AA):** deeper teal for supporting emphasis — version strings, the outer halo of the trefoil. Use it as a **text or stroke color on dark ground**, not as a fill: `accent-foreground` on `accent` is only 2.78:1 and fails WCAG AA.

### Status trio

| Token | Hex | Words | Meaning |
|---|---|---|---|
| `shipped` | #1DE4DB | SHIPPED | runtime proven |
| `signal` | #49DE78 | HEALTHY | live signal, success, positive delta |
| `partial` | #E5C057 | PARTIAL · DEGRADED | in progress, warning, caveat |
| `spec` | #7A898F | SPECIFIED · OFFLINE | specified only, inert, not started |

`BrandStatus` in `AndromedaChrome.swift` is the canonical mapping from status word to color.

### Light theme (web only)

The website ships a light theme with the same token names; values are listed under `light-*` in the front matter. Cyan deepens to `#008B8C` to stay legible on bright ground, and status hues darken to hold contrast. Native and TUI surfaces are dark-only.

### Source format

`globals.css` authors colors in **oklch**; the hex values here are their exact sRGB conversions. Keep authoring in oklch on the web and regenerate the hex values from it — never hand-tune a hex.

## Typography

A committed three-family system:

- **Instrument Serif** (400, roman + italic) — display and section titles only. Editorial, tight tracking (`-0.025em`). Italic is used for single emphasized phrases inside a headline, e.g. *visible, durable, graph-aware*.
- **Space Grotesk** (300–600) — body and all UI. Body is 16px at 1.625 line height. H2 is the only sans heading, at 600.
- **JetBrains Mono** — machine truth: capability IDs (`memory.recall`, `infer.write`, `project.state.*`), paths, status words, version strings, field keys, commands.

The **eyebrow** is the signature label: mono, uppercase, `0.3em` tracking, in `primary`, usually preceded by a 32px hairline in `primary/60`. In the TUI it is rendered as letter-spaced uppercase.

SwiftUI maps families to system designs: `AndromedaTheme.display()` → `.serif`, `AndromedaTheme.mono()` → `.monospaced`, body → default system. Always use `Font.TextStyle` so Dynamic Type scales.

## Layout

- Content column: `max-w-6xl` (72rem) with a 24px side gutter.
- Sections are separated by a 56px top margin, a hairline `border-t border-border/60`, and 40px of top padding.
- Cards use 24px (`p-6`) padding; tiles 32px.
- Grids: 1 column on mobile, 2 at `sm`, 3 at `lg`. Gap 16–24px.
- The dotted-grid canvas (`bg-dotgrid`) uses a 22px pitch and sits behind the floating bar only.

## Elevation & Depth

Depth is **tonal, not shadowed.** Surfaces rise by stepping from `background` → `popover` → `card`, each outlined with a 1px `border`. Do not add drop shadows to cards or bars.

Light is the only "elevation" effect, and it is always cyan:

- **Orbital pulse** (`animate-orbital`): a 2.6s breathing ring on the live center of the floating bar and on live status dots.
- **Starfield / aurora** (`bg-starfield`): sparse 1px cyan points as atmosphere behind hero and manifesto bands.
- **Drift** (14s rotation) and **pan** (90s starfield pan) for ambient motion; **marquee** (32s) for the principles ticker.

All motion is disabled under `prefers-reduced-motion`. On macOS, respect *Reduce Motion* the same way.

## Shapes

Base radius is **14px** (`--radius: 0.875rem`; `AndromedaTheme.cornerRadius`). Derived steps: `sm` 10px, `md` 12px, `lg` 14px, `xl` 18px.

- Buttons, cards, swatches: `rounded-xl` (12px).
- App icon tile: `rounded-2xl`.
- Capability chips, status chips, pills: fully rounded capsules.
- Inline code tokens (`memory.store`): 6px.
- Status dots: 6px circles.

## Components

- **Primary button:** cyan fill, `primary-foreground` text, 12px radius, `px-5 py-3`, medium weight. One per view.
- **Secondary button:** `card` fill, 1px border, hover shifts the border to `primary/50`. No fill change.
- **Card / Tile:** `card` fill, 1px border, 12px radius, 24px padding. Labels inside tiles are `mono-caption`, uppercase, `muted-foreground`.
- **Capability token:** `secondary` fill, mono text, 6px radius — for a single capability ID inline.
- **Capability chip:** capsule, `card` fill, 1px border, mono text — for lists of capabilities or craft tags.
- **Status chip:** 6px dot + uppercase mono word in the status color, on a 14% tint of the same color, capsule. Accessibility label is `"Status <WORD>"`.
- **Eyebrow + display pair:** hairline + eyebrow, then a serif display headline. The default section opener on every surface, including the TUI banner.
- **Field row (TUI and HUD):** key in `muted-foreground`, padded to 12 columns; value in `foreground`, or a status chip.
- **Caveat callout:** amber `CAVEAT` lead-in in `partial`, body in `foreground`. Used to disclose limits honestly.
- **Logo:** the trefoil mark needs breathing room and a dark field. On the TUI it is painted halo → accent → cyan core.

## Platform notes

### Web (`web/`)
- Use Tailwind semantic utilities only: `bg-card`, `text-muted-foreground`, `border-border`, `text-primary`. Never raw hex or Tailwind palette colors (`cyan-400`, `gray-800`).
- Opacity modifiers on tokens are allowed (`border-border/60`, `bg-primary/60`).
- Theme switching is `next-themes` on `<html class="dark">`; light values live under `:root`.
- Icons: `lucide-react`, 16px in UI text, stroke matches text color.

### macOS / SwiftUI
- Read every color from `AndromedaTheme` — never `Color.cyan`, `Color.green`, `.blue`, or system accent.
- Use `AndromedaStatusChip` for any state display.
- Prefer `Font.TextStyle`-based APIs so Dynamic Type works; use `AndromedaTheme.mono(_:)` and `.display(_:)` for the brand faces.
- SF Symbols in `.monochrome` or `.hierarchical` rendering, tinted with brand tokens.
- Every native surface stays agent-drivable (`/state`, `/action`, `/screenshot`) and previewable. Full craft rules: `docs/SWIFT-UI-DESIGN-RESOURCE.md`.

### CLI / TUI
- Print through `AndromedaChrome` only. Color degrades truecolor → 256 → plain; `NO_COLOR` is absolute.
- The banner is: trefoil, wordmark, eyebrow (surface name), tagline, version in `accent`, hairline.

## Do's and Don'ts

**Do**
- Use exactly one cyan-led focal point per view.
- Pair every status color with its uppercase mono word.
- Use mono for anything a machine produced or would parse.
- Get depth from tonal steps and hairlines.
- State limits plainly with a CAVEAT callout instead of hiding them.
- Change a token here, in `globals.css`, and in `AndromedaPalette.swift` in the same commit.

**Don't**
- Don't communicate status by color alone — not on the web, in SwiftUI, or in the terminal.
- Don't introduce a color that isn't a token in this file. No purples, no gradients outside the cyan glow, no rainbow charts.
- Don't use drop shadows on cards, bars, or chips.
- Don't greenwash: never show SHIPPED or HEALTHY for something that is partial or specified.
- Don't set body text in Instrument Serif, or headlines in mono.
- Don't use the cyan as a large background fill behind paragraphs.
- Don't put text on an `accent` fill (`bg-accent text-accent-foreground`); it fails contrast.
- Don't expose provider or vendor brands (Linear, Multica, n8n, model providers) in client-facing UI; surfaces show capabilities (`memory.*`, `infer.write`, `project.state.*`) only.
- Don't add motion that ignores reduced-motion settings.

## Agent Prompt Guide

When generating any Andromeda UI:

1. Read this file first. Tokens in the front matter are normative; prose explains how to apply them.
2. On the web, express everything through the Tailwind semantic utilities backed by `globals.css`. In Swift, through `AndromedaTheme` / `AndromedaPalette`. In the terminal, through `AndromedaChrome`.
3. If you need a value that isn't here, stop and propose a new token rather than inventing one inline.
4. Open new sections with the eyebrow + serif display pair.
5. Before finishing, check: one cyan focal point, status words present, no raw colors, reduced motion respected.
