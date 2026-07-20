import { PILLARS } from "@/lib/pillars"
import { SectionHeading } from "./pillars-section"
import { StatusDot } from "./status-dot"

export function Roadmap() {
  const memory = PILLARS.find((p) => p.key === "memory")!
  const rest = PILLARS.filter((p) => p.key !== "memory")
  const MemIcon = memory.icon

  return (
    <section id="roadmap" className="relative border-t border-border/60 py-20">
      <div className="mx-auto max-w-6xl px-6">
        <SectionHeading
          eyebrow="Roadmap · six pillars, one curtain"
          title="Building Memory first"
          desc="Anima is where we are now. The rest of the control plane follows the same rule — clients call stable capability IDs; Andromeda resolves providers, secrets, and processes behind the curtain."
        />

        {/* Now: Memory */}
        <div className="mt-12 rounded-2xl border border-primary/40 bg-card/60 p-6 md:p-8">
          <div className="flex flex-wrap items-center gap-3">
            <span className="flex h-12 w-12 items-center justify-center rounded-xl border border-primary/40 bg-secondary text-primary">
              <MemIcon className="h-6 w-6" />
            </span>
            <div>
              <div className="flex items-center gap-2">
                <span className="rounded-full bg-primary/15 px-2.5 py-0.5 font-mono text-[11px] uppercase tracking-wider text-primary">
                  Now
                </span>
                <h3 className="text-xl font-semibold">
                  {memory.name} <span className="font-mono text-sm text-primary/80">/ {memory.short}</span>
                </h3>
              </div>
              <p className="mt-1 text-sm font-medium text-primary">{memory.tagline}</p>
            </div>
            <div className="ml-auto">
              <StatusDot status={memory.status} withLabel />
            </div>
          </div>
          <p className="mt-4 max-w-3xl text-sm leading-relaxed text-muted-foreground">{memory.description}</p>
          <div className="mt-4 flex flex-wrap gap-1.5">
            {memory.capabilities.map((c) => (
              <span key={c} className="rounded-md bg-secondary px-2 py-1 font-mono text-[11px] text-secondary-foreground">
                {c}
              </span>
            ))}
          </div>
        </div>

        {/* Next: the other pillars */}
        <p className="mb-4 mt-8 font-mono text-[11px] uppercase tracking-[0.3em] text-muted-foreground">On the roadmap</p>
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          {rest.map((p) => {
            const Icon = p.icon
            return (
              <article
                key={p.key}
                className="group flex flex-col rounded-2xl border border-border bg-card/40 p-6 transition-all hover:border-primary/30 hover:bg-card/70"
              >
                <div className="mb-4 flex items-center justify-between">
                  <span className="flex h-10 w-10 items-center justify-center rounded-xl border border-border bg-secondary text-muted-foreground transition-colors group-hover:text-primary">
                    <Icon className="h-5 w-5" />
                  </span>
                  <StatusDot status={p.status} withLabel />
                </div>
                <div className="flex items-baseline gap-2">
                  <span className="font-mono text-xs text-muted-foreground">{String(p.index).padStart(2, "0")}</span>
                  <h3 className="font-semibold">{p.name}</h3>
                </div>
                <p className="mt-1 text-sm font-medium text-primary/90">{p.tagline}</p>
                <p className="mt-3 text-sm leading-relaxed text-muted-foreground">{p.description}</p>
              </article>
            )
          })}
        </div>
      </div>
    </section>
  )
}
