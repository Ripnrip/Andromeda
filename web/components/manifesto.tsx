export function Manifesto() {
  return (
    <section className="relative overflow-hidden border-t border-border/60 py-28">
      {/* Panning starfield atmosphere */}
      <div aria-hidden className="pointer-events-none absolute inset-0 bg-starfield animate-pan opacity-60" />
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0"
        style={{
          background:
            "radial-gradient(70% 60% at 50% 30%, oklch(0.28 0.07 195 / 0.45), transparent 70%)",
        }}
      />

      <div className="relative mx-auto max-w-4xl px-6 text-center">
        <p className="mb-8 font-mono text-xs uppercase tracking-[0.4em] text-primary">The dispatch</p>

        <blockquote className="text-balance font-serif text-4xl leading-[1.15] tracking-tight md:text-6xl md:leading-[1.1]">
          Automation should feel like a{" "}
          <span className="italic text-primary" style={{ textShadow: "0 0 44px oklch(0.83 0.14 190 / 0.35)" }}>
            lit horizon
          </span>{" "}
          — every worker visible, every memory provenanced, every capability behind a curtain you control.
        </blockquote>

        <div className="mx-auto mt-12 flex max-w-2xl items-center gap-4">
          <span aria-hidden className="h-px flex-1 bg-border/70" />
          <span className="font-mono text-xs uppercase tracking-[0.3em] text-muted-foreground">
            Andromeda Charter
          </span>
          <span aria-hidden className="h-px flex-1 bg-border/70" />
        </div>

        <div className="mt-10 grid gap-6 text-left sm:grid-cols-3">
          {[
            { k: "Local-first", v: "Your machine is the runtime. The cloud is optional, never required." },
            { k: "Graph-aware", v: "Memory is a provenanced graph — recall with lineage, not vibes." },
            { k: "Curtain-guarded", v: "Stable capability IDs in; provider brands never leak out." },
          ].map((c) => (
            <div key={c.k}>
              <p className="font-serif text-xl text-foreground">{c.k}</p>
              <p className="mt-2 text-sm leading-relaxed text-muted-foreground">{c.v}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
