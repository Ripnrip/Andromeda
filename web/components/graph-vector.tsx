import { STORES, LIBRARIAN, SEQUENCES } from "@/lib/memory"
import { SectionHeading } from "./pillars-section"
import { Network, Radar, BookOpen } from "lucide-react"
import { SequenceDiagram } from "./sequence-diagram"

export function GraphVector() {
  return (
    <section id="recall" className="relative border-t border-border/60 py-20">
      <div className="mx-auto max-w-6xl px-6">
        <SectionHeading
          eyebrow="Why graph AND vector"
          title="Similar is not the same as related"
          desc="A vector store finds things that are similar by meaning. A graph finds things that are related by connection. You need both — and most memory products only ship one."
        />

        <div className="mt-12 grid gap-4 lg:grid-cols-2">
          {/* Graph card */}
          <div className="rounded-2xl border border-primary/30 bg-card/60 p-6">
            <div className="mb-4 flex items-center gap-2">
              <Network className="h-5 w-5 text-primary" />
              <h3 className="font-semibold">A graph answers: what is connected to what?</h3>
            </div>
            <div className="rounded-xl border border-border bg-background/60 p-4 font-mono text-sm leading-relaxed">
              <span className="text-foreground">incident #412</span>{" "}
              <span className="text-primary">caused-by</span>{" "}
              <span className="text-foreground">deploy 8f2c</span>{" "}
              <span className="text-primary">touched</span> <span className="text-foreground">auth-service</span>{" "}
              <span className="text-primary">owned-by</span> <span className="text-foreground">platform-team</span>
            </div>
            <p className="mt-4 text-sm leading-relaxed text-muted-foreground">
              That is a chain of <span className="text-foreground">relations</span>. No embedding similarity will
              surface that structure — only a graph can walk the connection.
            </p>
          </div>

          {/* Vector card */}
          <div className="rounded-2xl border border-border bg-card/60 p-6">
            <div className="mb-4 flex items-center gap-2">
              <Radar className="h-5 w-5 text-primary" />
              <h3 className="font-semibold">A vector store answers: what does this mean?</h3>
            </div>
            <div className="rounded-xl border border-border bg-background/60 p-4 font-mono text-sm leading-relaxed">
              <span className="text-muted-foreground">query:</span> &ldquo;how do I roll back a bad migration?&rdquo;
              <br />
              <span className="text-primary">→ recall #1 @ 0.62</span>{" "}
              <span className="text-muted-foreground">— on a note whose exact words never appear</span>
            </div>
            <p className="mt-4 text-sm leading-relaxed text-muted-foreground">
              A <span className="text-foreground">meaning</span> query a graph can&apos;t do well — semantic retrieval
              surfacing the right note where keyword search would miss it entirely.
            </p>
          </div>
        </div>

        {/* Letta — master librarian */}
        <div className="mt-6 rounded-2xl border border-primary/40 bg-card/60 p-6">
          <div className="flex flex-col gap-6 lg:flex-row lg:items-start">
            <div className="lg:max-w-sm">
              <div className="mb-3 flex items-center gap-2">
                <BookOpen className="h-5 w-5 text-primary" />
                <span className="font-mono text-[11px] uppercase tracking-wider text-primary">
                  {LIBRARIAN.style}
                </span>
              </div>
              <h3 className="text-xl font-semibold text-balance">
                {LIBRARIAN.name} — {LIBRARIAN.role}
              </h3>
              <p className="mt-2 text-sm leading-relaxed text-muted-foreground">
                The backing stores each do one job.{" "}
                <span className="text-foreground">{LIBRARIAN.name}</span> is the layer that sits above them
                — {LIBRARIAN.answers}
              </p>
            </div>
            <ul className="flex-1 space-y-3">
              {LIBRARIAN.duties.map((duty, i) => (
                <li key={i} className="flex items-start gap-3">
                  <span className="mt-0.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-lg border border-primary/30 bg-primary/10">
                    <BookOpen className="h-3.5 w-3.5 text-primary" aria-hidden="true" />
                  </span>
                  <p className="text-sm leading-relaxed text-muted-foreground">{duty}</p>
                </li>
              ))}
            </ul>
          </div>
        </div>

        {/* Animated sequence diagrams */}
        <div className="mt-6 grid gap-4 lg:grid-cols-2">
          {SEQUENCES.map((seq) => (
            <SequenceDiagram key={seq.id} diagram={seq} stepDelay={480} />
          ))}
        </div>

        {/* Backing stores */}
        <div className="mt-4 rounded-2xl border border-border bg-card/40 p-6">
          <p className="mb-4 font-mono text-[11px] uppercase tracking-wider text-muted-foreground">
            Backing stores &middot; SoT = source of truth &middot; indexes are rebuildable
          </p>
          <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
            {STORES.map((s) => (
              <div key={s.name} className="rounded-xl border border-border/60 bg-background/40 p-3">
                <div className="flex flex-wrap items-center gap-1.5">
                  <code className="font-mono text-[12px] text-primary">{s.name}</code>
                  <span className="font-mono text-[10px] uppercase tracking-wide text-muted-foreground">{s.style}</span>
                  {s.isHot && (
                    <span className="rounded bg-primary/10 px-1 py-0.5 font-mono text-[9px] uppercase tracking-wide text-primary">
                      hot
                    </span>
                  )}
                  {s.isSoT && (
                    <span className="rounded bg-secondary px-1 py-0.5 font-mono text-[9px] uppercase tracking-wide text-foreground">
                      SoT
                    </span>
                  )}
                  {s.isIndex && (
                    <span className="rounded bg-border/60 px-1 py-0.5 font-mono text-[9px] uppercase tracking-wide text-muted-foreground">
                      index
                    </span>
                  )}
                </div>
                <p className="mt-2 text-xs leading-relaxed text-muted-foreground">{s.answers}</p>
              </div>
            ))}
          </div>
          <p className="mt-4 text-sm leading-relaxed text-muted-foreground">
            No single store does all of this well — that&apos;s why there are several.{" "}
            {LIBRARIAN.name} and Andromeda make them look like one to the client.
          </p>
        </div>
      </div>
    </section>
  )
}
