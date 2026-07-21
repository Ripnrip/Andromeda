import { MEMORY_LAYERS } from "@/lib/memory"
import { SectionHeading } from "./pillars-section"
import { StatusDot } from "./status-dot"
import { Sparkles } from "lucide-react"

export function MemoryLayers() {
  return (
    <section id="memory" className="relative border-t border-border/60 py-20">
      <div className="mx-auto max-w-6xl px-6">
        <SectionHeading
          eyebrow="Active build track · pillar 01"
          title="A closer look at Memory"
          desc="Anima is the first pillar under active construction, not the boundary of Andromeda. Its design treats memory as eight distinct jobs rather than a chat log with RAG — including Integrity, Awareness, and Dreaming."
        />

        <div className="mt-12 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {MEMORY_LAYERS.map((l) => (
            <article
              key={l.n}
              className={`group relative flex flex-col rounded-2xl border bg-card/60 p-5 transition-all hover:bg-card ${
                l.differentiator ? "border-primary/40" : "border-border hover:border-primary/30"
              }`}
            >
              <div className="mb-3 flex items-center justify-between">
                <span className="font-mono text-xs text-muted-foreground">{l.n}</span>
                <StatusDot status={l.status} withLabel />
              </div>
              <div className="flex items-center gap-1.5">
                <h3 className="text-lg font-semibold">{l.name}</h3>
                {l.differentiator && <Sparkles className="h-3.5 w-3.5 text-primary" aria-label="Differentiator" />}
              </div>
              <p className="mt-2 text-sm leading-relaxed text-muted-foreground">{l.intent}</p>
            </article>
          ))}
        </div>

        <p className="mt-6 flex items-center gap-2 font-mono text-xs text-muted-foreground">
          <Sparkles className="h-3.5 w-3.5 text-primary" />
          Differentiators: it can prove a memory is trustworthy, knows when <em>not</em> to interrupt, and Dreaming
          consolidates overnight so the morning is smarter.
        </p>
      </div>
    </section>
  )
}
