import { PILLARS } from "@/lib/pillars"
import { StatusDot } from "./status-dot"

export function PillarsSection() {
  return (
    <section id="pillars" className="relative border-t border-border/60 py-20">
      <div className="mx-auto max-w-6xl px-6">
        <SectionHeading
          eyebrow="Six pillars · one curtain"
          title="What Andromeda owns"
          desc="Memory, MCP host, Skills, LLM proxy, Secrets broker, and Fleet runtime — clients call stable capability IDs; Andromeda resolves providers, secrets, and processes server-side."
        />

        <div className="mt-12 grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          {PILLARS.map((p) => {
            const Icon = p.icon
            return (
              <article
                key={p.key}
                className="group relative flex flex-col rounded-2xl border border-border bg-card/60 p-6 transition-all hover:border-primary/40 hover:bg-card"
              >
                <div className="mb-4 flex items-center justify-between">
                  <span className="flex h-11 w-11 items-center justify-center rounded-xl border border-border bg-secondary text-primary transition-colors group-hover:border-primary/40">
                    <Icon className="h-5 w-5" />
                  </span>
                  <StatusDot status={p.status} withLabel />
                </div>

                <div className="flex items-baseline gap-2">
                  <span className="font-mono text-xs text-muted-foreground">
                    {String(p.index).padStart(2, "0")}
                  </span>
                  <h3 className="text-lg font-semibold">{p.name}</h3>
                  <span className="font-mono text-xs text-primary/80">/ {p.short}</span>
                </div>
                <p className="mt-1 text-sm font-medium text-primary">{p.tagline}</p>
                <p className="mt-3 text-sm leading-relaxed text-muted-foreground">{p.description}</p>

                <div className="mt-4 flex flex-wrap gap-1.5 border-t border-border/60 pt-4">
                  {p.capabilities.map((c) => (
                    <span
                      key={c}
                      className="rounded-md bg-secondary px-2 py-1 font-mono text-[11px] text-secondary-foreground"
                    >
                      {c}
                    </span>
                  ))}
                </div>
              </article>
            )
          })}
        </div>
      </div>
    </section>
  )
}

export function SectionHeading({
  eyebrow,
  title,
  desc,
}: {
  eyebrow: string
  title: string
  desc?: string
}) {
  return (
    <div className="max-w-2xl">
      <div className="mb-3 flex items-center gap-3">
        <span className="h-px w-8 bg-primary/60" />
        <span className="font-mono text-xs uppercase tracking-[0.3em] text-primary">{eyebrow}</span>
      </div>
      <h2 className="text-balance text-3xl font-bold tracking-tight md:text-4xl">{title}</h2>
      {desc && <p className="mt-4 text-pretty leading-relaxed text-muted-foreground">{desc}</p>}
    </div>
  )
}
