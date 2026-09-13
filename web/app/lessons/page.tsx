import { SiteNav } from "@/components/site-nav"
import { SiteFooter } from "@/components/site-footer"
import Link from "next/link"
import { GATE, EXHIBITS, PRINCIPLE, DOWNLOADS } from "@/lib/lessons"

export const metadata = {
  title: "Andromeda — Lessons",
  description:
    "The fleet's living engineering canon: the 15-question review gate, anti-pattern exhibits, the log principle, and downloadable skills.",
}

function GateRow({ q }: { q: (typeof GATE)[number] }) {
  return (
    <li className="group grid gap-2 border-b border-border/40 py-5 sm:grid-cols-[3.5rem_1fr] sm:gap-6">
      <div className="font-mono text-sm text-muted-foreground">
        <span className={q.blocker ? "text-accent" : ""}>Q{q.n}</span>
        {q.blocker && (
          <span className="mt-1 block text-[10px] uppercase tracking-wider text-accent/80">
            blocker
          </span>
        )}
      </div>
      <div>
        <h3 className="font-medium">{q.short}</h3>
        <p className="mt-1 text-sm leading-relaxed text-muted-foreground">
          {q.question}
        </p>
        <p className="mt-2 font-mono text-[11px] text-muted-foreground/70">
          from: {q.from}
        </p>
      </div>
    </li>
  )
}

export default function LessonsPage() {
  return (
    <main className="min-h-screen">
      <SiteNav />

      {/* Hero */}
      <section className="border-b border-border/40 px-6 py-20">
        <div className="mx-auto max-w-4xl">
          <p className="font-mono text-xs uppercase tracking-[0.2em] text-accent">
            The canon
          </p>
          <h1 className="mt-4 text-4xl font-semibold tracking-tight sm:text-5xl">
            Everything we broke, made law.
          </h1>
          <p className="mt-5 max-w-2xl text-lg leading-relaxed text-muted-foreground">
            A living resource from building Andromeda, the vault widget, the MCP
            hub, and a fleet of agents that review each other. Every lesson here
            came from a real incident with receipts — not from a style guide.
            Take the skills; they&apos;re versioned in git and mirrored for every
            agent we run.
          </p>
          <div className="mt-8 flex flex-wrap gap-3 font-mono text-xs">
            <span className="rounded-full border border-border/60 px-3 py-1.5">
              15 questions
            </span>
            <span className="rounded-full border border-border/60 px-3 py-1.5">
              6 merge blockers
            </span>
            <span className="rounded-full border border-border/60 px-3 py-1.5">
              14 exhibits
            </span>
            <span className="rounded-full border border-border/60 px-3 py-1.5">
              1 contract
            </span>
          </div>
        </div>
      </section>

      {/* The principle */}
      <section className="border-b border-border/40 px-6 py-16">
        <div className="mx-auto max-w-4xl">
          <p className="font-mono text-xs uppercase tracking-[0.2em] text-accent">
            The principle
          </p>
          <blockquote className="mt-6 border-l-2 border-accent/50 pl-6 text-2xl font-medium leading-snug tracking-tight sm:text-3xl">
            {PRINCIPLE.lines[0]}
          </blockquote>
          <ul className="mt-8 space-y-3">
            {PRINCIPLE.lines.slice(1).map((l) => (
              <li key={l} className="flex gap-3 text-muted-foreground">
                <span className="mt-1 text-accent">·</span>
                <span className="leading-relaxed">{l}</span>
              </li>
            ))}
          </ul>
          <p className="mt-6 font-mono text-[11px] text-muted-foreground/70">
            {PRINCIPLE.provenance}
          </p>
        </div>
      </section>

      {/* The gate */}
      <section className="border-b border-border/40 px-6 py-16" id="gate">
        <div className="mx-auto max-w-4xl">
          <p className="font-mono text-xs uppercase tracking-[0.2em] text-accent">
            The 15-question gate
          </p>
          <h2 className="mt-3 text-3xl font-semibold tracking-tight">
            Every PR answers before merge.
          </h2>
          <p className="mt-4 max-w-2xl text-muted-foreground">
            Six are merge blockers — unchecked means not mergeable. The rest need
            an explicit N/A. The mechanical subset belongs in pre-commit and CI;
            the judgment tier belongs to reviewers walking the list.
          </p>
          <ol className="mt-10">
            {GATE.map((q) => (
              <GateRow key={q.n} q={q} />
            ))}
          </ol>
        </div>
      </section>

      {/* Exhibits */}
      <section className="border-b border-border/40 px-6 py-16">
        <div className="mx-auto max-w-4xl">
          <p className="font-mono text-xs uppercase tracking-[0.2em] text-accent">
            Anti-pattern exhibits
          </p>
          <h2 className="mt-3 text-3xl font-semibold tracking-tight">
            Failure museums, curated from production.
          </h2>
          <div className="mt-10 grid gap-6 sm:grid-cols-2">
            {EXHIBITS.map((e) => (
              <div
                key={e.n}
                className="rounded-xl border border-border/60 bg-secondary/30 p-6"
              >
                <p className="font-mono text-xs text-accent">Exhibit {e.n}</p>
                <h3 className="mt-2 font-medium">{e.title}</h3>
                <p className="mt-2 text-sm text-muted-foreground">
                  <span className="text-foreground/80">Symptom:</span> {e.symptom}
                </p>
                <p className="mt-1 text-sm text-muted-foreground">
                  <span className="text-foreground/80">Rule:</span> {e.rule}
                </p>
                <p className="mt-3 font-mono text-[11px] text-muted-foreground/70">
                  {e.provenance}
                </p>
              </div>
            ))}
          </div>
          <p className="mt-6 font-mono text-[11px] text-muted-foreground/70">
            Exhibits 1–6, 8–12 live in the swift-canon download — from
            &ldquo;the tolerant record lane&rdquo; to &ldquo;the Go-shaped actor.&rdquo;
          </p>
        </div>
      </section>

      {/* Downloads */}
      <section className="px-6 py-16" id="downloads">
        <div className="mx-auto max-w-4xl">
          <p className="font-mono text-xs uppercase tracking-[0.2em] text-accent">
            Take it with you
          </p>
          <h2 className="mt-3 text-3xl font-semibold tracking-tight">
            Skills, templates, canon — latest from git.
          </h2>
          <p className="mt-4 max-w-2xl text-muted-foreground">
            These bundle from the repository&apos;s tracked sources on every
            build. The site is a projection; git is the log. If it&apos;s here,
            it&apos;s versioned.
          </p>
          <div className="mt-10 grid gap-4 sm:grid-cols-2">
            {DOWNLOADS.map((d) => (
              <a
                key={d.name}
                href={`/api/lessons/download?artifact=${encodeURIComponent(d.name)}`}
                className="group rounded-xl border border-border/60 bg-secondary/30 p-6 transition-colors hover:border-accent/40 hover:bg-secondary/60"
              >
                <div className="flex items-center justify-between">
                  <h3 className="font-medium">{d.name}</h3>
                  <span className="font-mono text-xs text-accent opacity-0 transition-opacity group-hover:opacity-100">
                    download ↓
                  </span>
                </div>
                <p className="mt-1 text-sm text-muted-foreground">{d.what}</p>
              </a>
            ))}
          </div>
        </div>
      </section>

      <SiteFooter />
    </main>
  )
}
