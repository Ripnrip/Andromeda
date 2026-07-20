const PROMISES = [
  "No silent loss",
  "No invisible automation",
  "No provider lock-in",
  "No knowledge without provenance",
  "No migration without rollback",
  "Local-first, always",
]

export function PromiseStrip() {
  // Rendered twice back-to-back so the -50% translate loops seamlessly.
  const lane = [...PROMISES, ...PROMISES]

  return (
    <section className="relative overflow-hidden border-y border-border/60 bg-card/30 py-4">
      {/* edge fades */}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-y-0 left-0 z-10 w-24"
        style={{ background: "linear-gradient(90deg, var(--background), transparent)" }}
      />
      <div
        aria-hidden
        className="pointer-events-none absolute inset-y-0 right-0 z-10 w-24"
        style={{ background: "linear-gradient(270deg, var(--background), transparent)" }}
      />

      <div className="flex w-max animate-marquee items-center gap-x-10" aria-label="Andromeda non-negotiables">
        {lane.map((p, i) => (
          <span key={`${p}-${i}`} className="flex shrink-0 items-center gap-3">
            <span className="font-serif text-lg italic text-foreground/90">{p}</span>
            <span aria-hidden className="text-primary/70">
              &#9670;
            </span>
          </span>
        ))}
      </div>
    </section>
  )
}
