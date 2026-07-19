import Image from "next/image"
import Link from "next/link"
import { ArrowLeft } from "lucide-react"
import { SiteNav } from "@/components/site-nav"
import { SiteFooter } from "@/components/site-footer"
import { AndromedaMark } from "@/components/andromeda-mark"
import { Wordmark } from "@/components/wordmark"
import { StatusDot } from "@/components/status-dot"

const SWATCHES = [
  { name: "Void", token: "--background", css: "oklch(0.16 0.018 210)", note: "Base surface" },
  { name: "Panel", token: "--card", css: "oklch(0.19 0.02 210)", note: "Cards / bars" },
  { name: "Slate", token: "--secondary", css: "oklch(0.24 0.022 210)", note: "Chips / hover" },
  { name: "Cyan Glow", token: "--primary", css: "oklch(0.83 0.14 190)", note: "Brand / action" },
  { name: "Teal", token: "--accent", css: "oklch(0.66 0.12 196)", note: "Accent" },
  { name: "Light", token: "--foreground", css: "oklch(0.95 0.012 200)", note: "Text" },
]

const SERIF_SCALE = [
  { label: "Display", cls: "font-serif text-6xl tracking-tight", sample: "Andromeda" },
  { label: "H1", cls: "font-serif text-4xl tracking-tight", sample: "The control plane" },
  { label: "Italic", cls: "font-serif text-3xl italic", sample: "visible, durable, graph-aware" },
]

const SANS_SCALE = [
  { label: "H2", cls: "text-2xl font-semibold", sample: "Six pillars, one curtain" },
  { label: "Body", cls: "text-base leading-relaxed", sample: "Local-first, Swift-native, graph-aware." },
  { label: "Label", cls: "font-mono text-xs uppercase tracking-[0.3em] text-primary", sample: "Type language" },
]

export default function DesignPage() {
  return (
    <main className="min-h-screen">
      <SiteNav />

      <div className="mx-auto max-w-6xl px-6 py-16">
        <Link
          href="/"
          className="mb-8 inline-flex items-center gap-2 font-mono text-xs text-muted-foreground transition-colors hover:text-foreground"
        >
          <ArrowLeft className="h-4 w-4" /> back to landing
        </Link>

        <div className="mb-3 flex items-center gap-3">
          <span className="h-px w-8 bg-primary/60" />
          <span className="font-mono text-xs uppercase tracking-[0.3em] text-primary">Design System</span>
        </div>
        <h1 className="text-balance font-serif text-5xl leading-[1.02] tracking-tight md:text-6xl">
          Andromeda visual language
        </h1>
        <p className="mt-4 max-w-2xl text-pretty leading-relaxed text-muted-foreground">
          Editorial type locked: <span className="font-serif italic text-foreground">Instrument Serif</span> for
          display, Space Grotesk for body and UI, JetBrains Mono for capability IDs. A deep-space system built
          from the logo — a glowing teal trefoil above a lit horizon.
        </p>

        {/* Logo */}
        <Block title="Logo" desc="The mark reads as a luminous trefoil. Give it breathing room and a dark field.">
          <div className="grid gap-4 sm:grid-cols-3">
            <Tile label="On void">
              <AndromedaMark size={72} />
            </Tile>
            <Tile label="App icon (contained)">
              <Image
                src="/andromeda-icon.png"
                alt="Andromeda app icon"
                width={96}
                height={96}
                className="rounded-2xl"
              />
            </Tile>
            <Tile label="Lockup">
              <Wordmark size="md" />
            </Tile>
          </div>
        </Block>

        {/* Color */}
        <Block title="Color" desc="Five-token palette. Cyan is the only saturated hue — used sparingly for action and glow.">
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {SWATCHES.map((s) => (
              <div key={s.token} className="overflow-hidden rounded-xl border border-border bg-card">
                <div className="h-20 w-full" style={{ background: s.css }} />
                <div className="flex items-center justify-between p-3">
                  <div>
                    <p className="text-sm font-medium">{s.name}</p>
                    <p className="text-xs text-muted-foreground">{s.note}</p>
                  </div>
                  <code className="font-mono text-[10px] text-muted-foreground">{s.token}</code>
                </div>
              </div>
            ))}
          </div>
        </Block>

        {/* Typography */}
        <Block
          title="Typography"
          desc="Committed to a three-family system: Instrument Serif for display, Space Grotesk for body and UI, JetBrains Mono for capability IDs, code, and metadata."
        >
          <div className="grid gap-6 lg:grid-cols-3">
            <div className="rounded-xl border border-border bg-card p-6">
              <p className="mb-4 font-mono text-xs uppercase tracking-wider text-muted-foreground">
                Instrument Serif — Display · roman + italic
              </p>
              <div className="space-y-3">
                {SERIF_SCALE.map((t) => (
                  <div key={t.label} className="flex items-baseline gap-4">
                    <span className="w-14 shrink-0 font-mono text-[10px] uppercase text-muted-foreground">
                      {t.label}
                    </span>
                    <span className={t.cls}>{t.sample}</span>
                  </div>
                ))}
              </div>
            </div>
            <div className="rounded-xl border border-border bg-card p-6">
              <p className="mb-4 font-mono text-xs uppercase tracking-wider text-muted-foreground">
                Space Grotesk — Body &amp; UI · 300–600
              </p>
              <div className="space-y-3">
                {SANS_SCALE.map((t) => (
                  <div key={t.label} className="flex items-baseline gap-4">
                    <span className="w-14 shrink-0 font-mono text-[10px] uppercase text-muted-foreground">
                      {t.label}
                    </span>
                    <span className={`font-sans ${t.cls}`}>{t.sample}</span>
                  </div>
                ))}
              </div>
            </div>
            <div className="rounded-xl border border-border bg-card p-6">
              <p className="mb-4 font-mono text-xs uppercase tracking-wider text-muted-foreground">
                JetBrains Mono — Code / IDs
              </p>
              <div className="space-y-2 font-mono text-sm">
                <p>
                  <span className="text-primary">memory.recall</span>(&#123; query &#125;)
                </p>
                <p>
                  <span className="text-primary">infer.write</span> → gateway
                </p>
                <p className="text-muted-foreground">project.state.*</p>
                <p className="text-muted-foreground">$ swift run andromeda status</p>
                <p className="text-muted-foreground">0123456789 · ●◐○</p>
              </div>
            </div>
          </div>
        </Block>

        {/* Status system */}
        <Block title="Status system" desc="Honest status, never greenwashed. Three states across every pillar and capability.">
          <div className="flex flex-wrap gap-4">
            {(["shipped", "partial", "spec"] as const).map((s) => (
              <div key={s} className="flex items-center gap-3 rounded-xl border border-border bg-card px-5 py-4">
                <StatusDot status={s} pulse />
                <div>
                  <StatusDot status={s} withLabel />
                  <p className="mt-1 font-mono text-[11px] text-muted-foreground">
                    {s === "shipped" ? "runtime proven" : s === "partial" ? "in progress" : "specified only"}
                  </p>
                </div>
              </div>
            ))}
          </div>
        </Block>

        {/* Components */}
        <Block title="Components" desc="Core surfaces used across the system.">
          <div className="flex flex-wrap items-center gap-4">
            <button className="rounded-xl bg-primary px-5 py-3 font-medium text-primary-foreground">
              Primary action
            </button>
            <button className="rounded-xl border border-border bg-card px-5 py-3 font-medium hover:border-primary/50">
              Secondary
            </button>
            <span className="rounded-md bg-secondary px-2.5 py-1.5 font-mono text-xs text-secondary-foreground">
              memory.store
            </span>
            <span className="rounded-full border border-border bg-card px-3 py-1.5 font-mono text-xs">
              capability chip
            </span>
          </div>
        </Block>
      </div>

      <SiteFooter />
    </main>
  )
}

function Block({ title, desc, children }: { title: string; desc: string; children: React.ReactNode }) {
  return (
    <section className="mt-14 border-t border-border/60 pt-10">
      <h2 className="font-serif text-3xl tracking-tight">{title}</h2>
      <p className="mt-1.5 max-w-2xl text-sm leading-relaxed text-muted-foreground">{desc}</p>
      <div className="mt-6">{children}</div>
    </section>
  )
}

function Tile({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col items-center justify-center gap-4 rounded-xl border border-border bg-card p-8">
      <div className="flex h-24 items-center justify-center">{children}</div>
      <span className="font-mono text-[10px] uppercase tracking-wider text-muted-foreground">{label}</span>
    </div>
  )
}
