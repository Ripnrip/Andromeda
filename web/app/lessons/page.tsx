import Link from "next/link"
import type { Metadata } from "next"
import { Download } from "lucide-react"
import { LessonsShell } from "@/components/lessons-shell"
import { StatusDot } from "@/components/status-dot"
import { KIND_LABEL, LESSONS } from "@/lib/lessons"

export const metadata: Metadata = {
  title: "Lessons — Andromeda",
  description:
    "Living fleet craft: Swift Canon, the 15-question review gate, PR templates, AndromedaUI, App Control, anti-patterns, and sequence-diagram law. Download the latest pack.",
}

const PACK = [
  { href: "/lessons/pack/swift-review-gate.md", label: "swift-review-gate.md" },
  { href: "/lessons/pack/swift-canon.md", label: "swift-canon.md" },
  { href: "/lessons/pack/anti-patterns.md", label: "anti-patterns.md" },
  { href: "/lessons/pack/PULL_REQUEST_TEMPLATE.md", label: "PULL_REQUEST_TEMPLATE.md" },
  { href: "/lessons/pack/app-control.md", label: "app-control.md" },
  { href: "/lessons/pack/sequence-diagram.mmd", label: "sequence-diagram.mmd" },
  { href: "/lessons/pack/README.md", label: "README.md" },
]

export default function LessonsIndexPage() {
  return (
    <LessonsShell>
      <header className="max-w-2xl">
        <div className="mb-3 flex items-center gap-3">
          <span className="h-px w-8 bg-primary/60" />
          <span className="font-mono text-xs uppercase tracking-[0.3em] text-primary">Living resource</span>
        </div>
        <h1 className="text-balance font-serif text-5xl leading-[1.02] tracking-tight md:text-6xl">
          What we actually learned
        </h1>
        <p className="mt-4 text-pretty leading-relaxed text-muted-foreground">
          Not a blog. The fleet contract — canon, the 15-question gate, PR templates, AndromedaUI
          rules, and how to drive the UI from tests and agents. Git is the source of truth. This
          page is a projection. When a lesson changes, it changes in the same PR as the skill.
        </p>
      </header>

      <div className="mt-10 overflow-x-auto rounded-2xl border border-border bg-card/40">
        <table className="w-full min-w-[640px] text-left text-sm">
          <thead>
            <tr className="border-b border-border font-mono text-[11px] uppercase tracking-wider text-muted-foreground">
              <th className="px-4 py-3 font-medium">Artifact</th>
              <th className="px-4 py-3 font-medium">Kind</th>
              <th className="px-4 py-3 font-medium">Honesty</th>
              <th className="px-4 py-3 font-medium">Get</th>
            </tr>
          </thead>
          <tbody>
            {LESSONS.map((l) => (
              <tr key={l.slug} className="border-b border-border/60 last:border-0">
                <td className="px-4 py-3">
                  <Link href={`/lessons/${l.slug}`} className="font-medium hover:text-primary">
                    {l.title}
                  </Link>
                  <p className="mt-0.5 max-w-md text-xs leading-relaxed text-muted-foreground">
                    {l.summary}
                  </p>
                </td>
                <td className="px-4 py-3 font-mono text-xs text-muted-foreground">{KIND_LABEL[l.kind]}</td>
                <td className="px-4 py-3">
                  <StatusDot status={l.status} withLabel />
                </td>
                <td className="px-4 py-3">
                  {l.downloads[0] ? (
                    <a
                      href={l.downloads[0].href}
                      download={l.downloads[0].filename}
                      className="inline-flex items-center gap-1.5 font-mono text-xs text-primary hover:underline"
                    >
                      <Download className="h-3.5 w-3.5" />
                      {l.downloads[0].label}
                    </a>
                  ) : (
                    <span className="font-mono text-xs text-muted-foreground">read only</span>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <section id="pack" className="mt-14 scroll-mt-24">
        <h2 className="font-serif text-3xl tracking-tight">Download pack</h2>
        <p className="mt-2 max-w-2xl text-sm leading-relaxed text-muted-foreground">
          Drop these into <code className="font-mono text-foreground">~/.agents/skills/</code>,{" "}
          <code className="font-mono text-foreground">.claude/skills/</code>, or{" "}
          <code className="font-mono text-foreground">.github/</code>. They are the copies this
          site ships — if git moved on, prefer the GitHub tree linked on each lesson.
        </p>
        <ul className="mt-5 divide-y divide-border/60 rounded-2xl border border-border bg-card/40">
          {PACK.map((f) => (
            <li key={f.href} className="flex items-center justify-between gap-4 px-4 py-3">
              <span className="font-mono text-sm">{f.label}</span>
              <a
                href={f.href}
                download
                className="inline-flex items-center gap-1.5 font-mono text-xs text-primary hover:underline"
              >
                <Download className="h-3.5 w-3.5" />
                download
              </a>
            </li>
          ))}
        </ul>
      </section>
    </LessonsShell>
  )
}
