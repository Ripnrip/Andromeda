import { Activity, Route, Eye } from "lucide-react"

const VALUES = [
  {
    icon: Activity,
    title: "Make the invisible visible",
    body: "Agents, jobs, daemons, and scheduled work should report into one observable surface — not disappear across terminals, machines, and background processes.",
  },
  {
    icon: Route,
    title: "Give clients stable capabilities",
    body: "Clients ask localhost for memory, tools, models, skills, or secrets by capability ID. Andromeda resolves the provider and policy behind the curtain.",
  },
  {
    icon: Eye,
    title: "Keep control local",
    body: "The control plane, audit trail, routing rules, and human kill switch stay yours — even when the providers behind them change.",
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
