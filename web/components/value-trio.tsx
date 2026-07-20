import { Layers, EyeOff, Droplets } from "lucide-react"

const VALUES = [
  {
    icon: Layers,
    title: "Control the chaos",
    body: "Many agents, many jobs, many days of work — brought into one observable place instead of scattered across terminals and transcripts.",
  },
  {
    icon: EyeOff,
    title: "Conceal the complexity",
    body: "Several specialized stores sit behind one simple curtain. Clients ask a question; they never see the machinery that answers it.",
  },
  {
    icon: Droplets,
    title: "Stop paying the evaporation tax",
    body: "The river of fixes, decisions, and root causes each day is distilled into durable memory — not lost the moment a session closes.",
  },
]

export function ValueTrio() {
  return (
    <section className="relative border-b border-border/60 py-20">
      <div className="mx-auto max-w-6xl px-6">
        <p className="mb-3 text-center font-mono text-xs uppercase tracking-[0.3em] text-primary">What it&apos;s for</p>
        <h2 className="mx-auto max-w-3xl text-balance text-center font-serif text-4xl leading-[1.05] tracking-tight md:text-5xl">
          The problems that pushed us to build Andromeda
        </h2>

        <div className="mt-14 grid gap-4 md:grid-cols-3">
          {VALUES.map(({ icon: Icon, title, body }) => (
            <div key={title} className="rounded-2xl border border-border bg-card/60 p-6">
              <div className="flex h-10 w-10 items-center justify-center rounded-xl border border-primary/30 bg-primary/10">
                <Icon className="h-5 w-5 text-primary" />
              </div>
              <h3 className="mt-4 font-serif text-2xl tracking-tight">{title}</h3>
              <p className="mt-2 text-sm leading-relaxed text-muted-foreground">{body}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
