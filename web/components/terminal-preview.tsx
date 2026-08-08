import { COMPACT_MARK, FULL_MARK, SHADE_CLASS, WORDMARK, shadeFor } from "@/lib/ascii-mark"

/** Renders ASCII art with the logo's glow shading (halo → accent → core). */
function GlowArt({ lines, className = "" }: { lines: string[]; className?: string }) {
  return (
    <pre
      aria-hidden
      className={`overflow-x-auto font-mono text-[9px] leading-[1.15] sm:text-[11px] ${className}`}
    >
      {lines.map((line, row) => (
        <div key={row}>
          {Array.from(line).map((character, column) => (
            <span key={column} className={SHADE_CLASS[shadeFor(character)]}>
              {character === " " ? "\u00A0" : character}
            </span>
          ))}
        </div>
      ))}
    </pre>
  )
}

const CHIPS = [
  { word: "SHIPPED", cls: "text-shipped" },
  { word: "PARTIAL", cls: "text-partial" },
  { word: "SPECIFIED", cls: "text-spec" },
  { word: "HEALTHY", cls: "text-signal" },
  { word: "DEGRADED", cls: "text-partial" },
  { word: "OFFLINE", cls: "text-spec" },
]

const FIELDS: [string, string][] = [
  ["surface", "autocache (Anthropic prompt-cache proxy)"],
  ["bind", "127.0.0.1:8080"],
  ["strategy", "moderate"],
]

/**
 * The terminal surface of the design system: the same tokens, mark and status
 * vocabulary the Swift `AndromedaBrand` module prints from `andromeda brand`.
 */
export function TerminalPreview() {
  return (
    <div className="grid gap-4 lg:grid-cols-2">
      <figure className="rounded-xl border border-border bg-card p-5">
        <figcaption className="mb-4 font-mono text-[10px] uppercase tracking-[0.3em] text-muted-foreground">
          Trefoil · full · 46 cols
        </figcaption>
        <GlowArt lines={FULL_MARK} />
      </figure>

      <div className="flex flex-col gap-4">
        <figure className="rounded-xl border border-border bg-card p-5">
          <figcaption className="mb-4 font-mono text-[10px] uppercase tracking-[0.3em] text-muted-foreground">
            Trefoil · compact · 22 cols
          </figcaption>
          <GlowArt lines={COMPACT_MARK} />
        </figure>

        <figure className="rounded-xl border border-border bg-card p-5">
          <figcaption className="mb-4 font-mono text-[10px] uppercase tracking-[0.3em] text-muted-foreground">
            Wordmark lockup
          </figcaption>
          <pre className="overflow-x-auto font-mono text-[8px] leading-[1.15] text-foreground sm:text-[10px]">
            {WORDMARK.join("\n")}
          </pre>
        </figure>
      </div>

      <figure className="rounded-xl border border-border bg-card p-5 lg:col-span-2">
        <figcaption className="mb-4 font-mono text-[10px] uppercase tracking-[0.3em] text-muted-foreground">
          Chrome · eyebrow, fields, status chips, caveat
        </figcaption>
        <div className="space-y-1 font-mono text-xs">
          <p className="tracking-[0.4em] text-primary">A U T O C A C H E&nbsp;&nbsp;G A T E W A Y</p>
          <p className="text-border">{"─".repeat(52)}</p>
          {FIELDS.map(([key, value]) => (
            <p key={key}>
              <span className="text-muted-foreground">{key.padEnd(12, "\u00A0")}</span>
              <span className="text-foreground">{value}</span>
            </p>
          ))}
          <p>
            <span className="text-muted-foreground">{"pillar 4".padEnd(12, "\u00A0")}</span>
            <span className="text-partial">{"● PARTIAL"}</span>{" "}
            <span className="text-muted-foreground">LLM proxy — Anthropic surface only</span>
          </p>
          <p className="text-border">{"─".repeat(52)}</p>
          <p className="flex flex-wrap gap-x-5 gap-y-1">
            {CHIPS.map((chip) => (
              <span key={chip.word} className={chip.cls}>
                {"● "}
                {chip.word}
              </span>
            ))}
          </p>
          <p className="pt-2">
            <span className="font-semibold text-partial">CAVEAT</span>{" "}
            <span className="text-foreground">
              {"Colour degrades truecolor → 256 → plain; NO_COLOR is honoured."}
            </span>
          </p>
        </div>
      </figure>
    </div>
  )
}
