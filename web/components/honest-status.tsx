import { STATUS_BOARD } from "@/lib/memory"
import { SectionHeading } from "./pillars-section"
import { StatusDot } from "./status-dot"

export function HonestStatus() {
  return (
    <section id="status" className="relative border-t border-border/60 py-20">
      <div className="mx-auto max-w-6xl px-6">
        <SectionHeading
          eyebrow="Honest status · 2026-07-19"
          title="What is and isn't shipped"
          desc="A portfolio piece should be accurate. Here is the real state of the system today — no greenwashing."
        />

        <div className="mt-12 grid gap-4 lg:grid-cols-3">
          {STATUS_BOARD.map((col) => (
            <div key={col.status} className="flex flex-col rounded-2xl border border-border bg-card/60 p-6">
              <div className="mb-4 flex items-center gap-2 border-b border-border/60 pb-4">
                <StatusDot status={col.status} pulse />
                <h3 className="font-semibold">{col.heading}</h3>
                <span className="ml-auto font-mono text-xs text-muted-foreground">{col.items.length}</span>
              </div>
              <ul className="flex flex-col gap-3">
                {col.items.map((item) => (
                  <li key={item} className="flex gap-2 text-sm leading-relaxed text-muted-foreground">
                    <span className="mt-2 h-1 w-1 shrink-0 rounded-full bg-border" />
                    {item}
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>

        <p className="mt-6 rounded-xl border border-partial/30 bg-partial/5 px-4 py-3 text-sm leading-relaxed text-muted-foreground">
          <span className="font-mono text-xs uppercase tracking-wider text-partial">caveat</span>{" "}
          <code className="font-mono text-foreground">write.tool</code> is currently an episodic-store alias — not LLM
          inference. It becomes a real inference capability only through an explicit versioned migration. We don&apos;t
          advertise it as inference until then.
        </p>
      </div>
    </section>
  )
}
