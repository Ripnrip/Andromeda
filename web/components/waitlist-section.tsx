import { WaitlistForm } from "./waitlist-form"

export function WaitlistSection() {
  return (
    <section id="waitlist" className="relative overflow-hidden border-t border-border/60 py-24">
      <div aria-hidden className="pointer-events-none absolute inset-0 bg-starfield opacity-50" />
      <div
        aria-hidden
        className="pointer-events-none absolute inset-x-0 bottom-0 h-[420px]"
        style={{ background: "radial-gradient(60% 60% at 50% 100%, oklch(0.3 0.08 195 / 0.4), transparent 70%)" }}
      />

      <div className="relative mx-auto grid max-w-6xl items-center gap-12 px-6 lg:grid-cols-2">
        <div>
          <div className="mb-4 flex items-center gap-3">
            <span className="h-px w-8 bg-primary/60" />
            <span className="font-mono text-xs uppercase tracking-[0.3em] text-primary">Early access</span>
          </div>
          <h2 className="text-balance font-serif text-4xl leading-[1.05] tracking-tight md:text-5xl">
            Help shape the control plane we wish existed
          </h2>
          <p className="mt-4 max-w-lg text-pretty leading-relaxed text-muted-foreground">
            We&apos;re building Andromeda toward the open-source world: one local curtain for agents, jobs, tools,
            providers, secrets, and fleet state. Join for real milestones as the six pillars come online — no launch
            theater, no spam.
          </p>

          <ul className="mt-6 flex flex-col gap-2 font-mono text-xs text-muted-foreground">
            <li>· Local-first, not local-only</li>
            <li>· No knowledge without provenance</li>
            <li>· No automation without visibility</li>
            <li>· No migration without rollback</li>
          </ul>
        </div>

        <WaitlistForm />
      </div>
    </section>
  )
}
