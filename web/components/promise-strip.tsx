const PROMISES = [
  "No silent loss",
  "No invisible automation",
  "No provider lock-in",
  "No knowledge without provenance",
  "No migration without rollback",
]

export function PromiseStrip() {
  return (
    <section className="border-t border-border/60 bg-card/30 py-6">
      <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-center gap-x-8 gap-y-3 px-6">
        {PROMISES.map((p) => (
          <span key={p} className="flex items-center gap-2 font-mono text-sm text-muted-foreground">
            <span className="text-primary">/</span>
            {p}
          </span>
        ))}
      </div>
    </section>
  )
}
