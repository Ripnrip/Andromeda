import { STORES } from "@/lib/memory"
import { SectionHeading } from "./pillars-section"
import { Network, Radar } from "lucide-react"

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
          {/* Graph card — lead with the relation chain */}
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

        {/* Spectrum */}
        <div className="mt-6 rounded-2xl border border-border bg-card/40 p-6">
          <p className="mb-4 font-mono text-[11px] uppercase tracking-wider text-muted-foreground">
            One job per store · exact & durable → by meaning → by connection
          </p>
          <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-4">
            {STORES.map((s) => (
              <div key={s.name} className="rounded-xl border border-border/60 bg-background/40 p-3">
                <div className="flex items-center justify-between gap-2">
                  <code className="font-mono text-[12px] text-primary">{s.name}</code>
                  <span className="font-mono text-[10px] uppercase tracking-wide text-muted-foreground">{s.style}</span>
                </div>
                <p className="mt-2 text-xs leading-relaxed text-muted-foreground">{s.answers}</p>
              </div>
            ))}
          </div>
          <p className="mt-4 text-sm leading-relaxed text-muted-foreground">
            No single store does all of this well — that&apos;s why there are several. Andromeda&apos;s job is to make
            them look like one to the client.
          </p>
        </div>
      </div>
    </section>
  )
}
