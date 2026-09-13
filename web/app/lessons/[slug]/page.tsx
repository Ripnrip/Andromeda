import Link from "next/link"
import { notFound } from "next/navigation"
import type { Metadata } from "next"
import { Download, ExternalLink } from "lucide-react"
import { LessonsShell } from "@/components/lessons-shell"
import { StatusDot } from "@/components/status-dot"
import {
  CANON_REFERENCES,
  EXHIBITS,
  GATE_QUESTIONS,
  KIND_LABEL,
  LESSONS,
  NAMING_SPLIT,
  lessonBySlug,
} from "@/lib/lessons"

export function generateStaticParams() {
  return LESSONS.map((l) => ({ slug: l.slug }))
}

type LessonParams = { slug: string }

export async function generateMetadata({
  params,
}: {
  params: Promise<LessonParams>
}): Promise<Metadata> {
  const { slug } = await params
  const lesson = lessonBySlug(slug)
  if (!lesson) return { title: "Lessons — Andromeda" }
  return {
    title: `${lesson.title} — Andromeda Lessons`,
    description: lesson.summary,
  }
}

export default async function LessonPage({ params }: { params: Promise<LessonParams> }) {
  const { slug } = await params
  const lesson = lessonBySlug(slug)
  if (!lesson) notFound()

  return (
    <LessonsShell active={lesson.slug}>
      <p className="font-mono text-xs uppercase tracking-[0.3em] text-primary">{lesson.eyebrow}</p>
      <div className="mt-3 flex flex-wrap items-center gap-3">
        <h1 className="font-serif text-4xl tracking-tight md:text-5xl">{lesson.title}</h1>
        <StatusDot status={lesson.status} withLabel />
        <span className="font-mono text-xs text-muted-foreground">{KIND_LABEL[lesson.kind]}</span>
      </div>
      <p className="mt-4 max-w-2xl text-pretty leading-relaxed text-muted-foreground">{lesson.summary}</p>

      <div className="mt-6 flex flex-wrap gap-3">
        {lesson.downloads.map((d) => (
          <a
            key={d.href}
            href={d.href}
            download={d.filename}
            className="inline-flex items-center gap-2 rounded-lg border border-border bg-card px-3 py-2 font-mono text-xs text-foreground hover:border-primary/40 hover:text-primary"
          >
            <Download className="h-3.5 w-3.5" />
            {d.label}
          </a>
        ))}
        {lesson.github && (
          <a
            href={lesson.github}
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-2 rounded-lg border border-border px-3 py-2 font-mono text-xs text-muted-foreground hover:text-foreground"
          >
            <ExternalLink className="h-3.5 w-3.5" />
            git home
          </a>
        )}
        <Link
          href="/lessons"
          className="inline-flex items-center rounded-lg px-3 py-2 font-mono text-xs text-muted-foreground hover:text-foreground"
        >
          ← catalog
        </Link>
      </div>

      <div className="mt-10">{renderBody(lesson.slug)}</div>
    </LessonsShell>
  )
}

function renderBody(slug: string) {
  switch (slug) {
    case "review-gate":
      return <GateBody />
    case "swift-canon":
      return <CanonBody />
    case "anti-patterns":
      return <AntiBody />
    case "pr-template":
      return <TemplateBody />
    case "andromedaui":
      return <UiBody />
    case "app-control":
      return <AppControlBody />
    case "diagrams":
      return <DiagramsBody />
    default:
      return null
  }
}

function GateBody() {
  const groups = [...new Set(GATE_QUESTIONS.map((q) => q.group))]
  return (
    <div className="space-y-10">
      <p className="max-w-2xl text-sm leading-relaxed text-muted-foreground">
        Merge blockers are Q1, Q2, Q6, Q8, Q9, Q14. Pre-commit questions can become ast-grep/CI.
        Review questions need judgment — unchecked means an explicit rationale or N/A, not silence.
      </p>
      {groups.map((group) => (
        <section key={group}>
          <h2 className="font-serif text-2xl tracking-tight">{group}</h2>
          <ol className="mt-4 space-y-3">
            {GATE_QUESTIONS.filter((q) => q.group === group).map((q) => (
              <li
                key={q.id}
                className="rounded-2xl border border-border bg-card/50 p-4"
              >
                <div className="flex flex-wrap items-center gap-2">
                  <span className="font-mono text-xs text-primary">{q.id}</span>
                  <h3 className="font-medium">{q.title}</h3>
                  {q.blocker && (
                    <span className="rounded-full border border-partial/40 bg-partial/10 px-2 py-0.5 font-mono text-[10px] uppercase tracking-wider text-partial">
                      merge blocker
                    </span>
                  )}
                  <span className="font-mono text-[10px] uppercase tracking-wider text-muted-foreground">
                    {q.tier}
                  </span>
                </div>
                <p className="mt-2 text-sm leading-relaxed text-muted-foreground">{q.body}</p>
              </li>
            ))}
          </ol>
        </section>
      ))}
    </div>
  )
}

function CanonBody() {
  return (
    <div className="space-y-6">
      <p className="max-w-2xl text-sm leading-relaxed text-muted-foreground">
        Compiler truth first. Native over ornamental. Generated code stays generated. Tests match
        the change. No merge with unresolved substantive review comments — including findings that
        live only in a review <em>body</em>, not a thread.
      </p>
      <ul className="divide-y divide-border/60 rounded-2xl border border-border bg-card/40">
        {CANON_REFERENCES.map((r) => (
          <li key={r.file} className="flex items-baseline justify-between gap-4 px-4 py-2.5">
            <code className="font-mono text-xs text-foreground">{r.file}</code>
            <span className="text-xs text-muted-foreground">{r.use}</span>
          </li>
        ))}
      </ul>
    </div>
  )
}

function AntiBody() {
  return (
    <ol className="space-y-2">
      {EXHIBITS.map((e) => (
        <li key={e.id} className="rounded-xl border border-border bg-card/40 px-4 py-3">
          <p className="text-sm">
            <span className="font-mono text-xs text-primary">Exhibit {e.id}</span>{" "}
            <span className="font-medium">{e.title}</span>
          </p>
          {e.note && <p className="mt-1 text-xs text-muted-foreground">{e.note}</p>}
        </li>
      ))}
    </ol>
  )
}

function TemplateBody() {
  return (
    <div className="max-w-2xl space-y-4 text-sm leading-relaxed text-muted-foreground">
      <p>
        The template in git today already requires a mermaid sequence/flow diagram and visual
        evidence. The six merge-blocker checkboxes (Q1, Q2, Q6, Q8, Q9, Q14) are the follow-up so
        every PR opens with the gate staring at the author. Honesty: those boxes ride the review-gate
        workstream and may lag <code className="text-foreground">main</code> — the pack file is the
        intended latest.
      </p>
      <p>Required sections, in order: What / Why / Sequence diagram / Visual evidence / Test plan / Secrets posture / Blast radius / Review gate.</p>
    </div>
  )
}

function UiBody() {
  return (
    <div className="max-w-2xl space-y-4 text-sm leading-relaxed text-muted-foreground">
      <p>
        <code className="text-foreground">Packages/AndromedaUI</code> already has Control Plane
        views, preview parity, snapshots, and a11y tests. New components ship with:
      </p>
      <ul className="list-disc space-y-2 pl-5">
        <li>Caller-supplied stable accessibility identifiers — wrappers must not swallow them.</li>
        <li>No networking or business logic inside primitives (GlassCard, tabs, buttons).</li>
        <li>Preview states that double as screenshot subjects (loading / empty / error / long / Dynamic Type / dark).</li>
        <li>Rows keyed by stable data ids, never array index alone.</li>
        <li>Decorative motion is screenshot-only unless the user can interact with it.</li>
      </ul>
    </div>
  )
}

function AppControlBody() {
  return (
    <div className="space-y-8">
      <div className="grid gap-3 sm:grid-cols-2">
        {NAMING_SPLIT.map((n) => (
          <article key={n.name} className="rounded-2xl border border-border bg-card/40 p-4">
            <h3 className="font-medium">{n.name}</h3>
            <p className="mt-2 text-sm leading-relaxed text-muted-foreground">{n.meaning}</p>
          </article>
        ))}
      </div>
      <ol className="max-w-2xl list-decimal space-y-3 pl-5 text-sm leading-relaxed text-muted-foreground">
        <li>
          <strong className="text-foreground">Do not add a second HTTP host.</strong> App Control
          is new routes on the existing AndromedaHTTP router, env-gated (
          <code className="text-foreground">ANDROMEDA_APP_CONTROL=1</code>), loopback or the same
          bearer as /mcp.
        </li>
        <li>
          Identifiers: <code className="text-foreground">andromeda.&lt;pane&gt;.&lt;control&gt;</code>.
          Identifier ≠ accessibility label.
        </li>
        <li>
          Typed <code className="text-foreground">ControlAction</code> enum — unknown action is a
          loud 422, never a silent 200. Dispatcher calls the same methods the buttons call.
        </li>
        <li>
          Screenshots via ImageRenderer / off-screen AppKit — never{" "}
          <code className="text-foreground">screencapture</code>.
        </li>
        <li>
          CLI / MCP / OSA are translators after Gate 1 (curl proves human click ≡ POST /action).
          OSA waits for a real Andromeda.app bundle.
        </li>
      </ol>
    </div>
  )
}

function DiagramsBody() {
  return (
    <div className="max-w-2xl space-y-4 text-sm leading-relaxed text-muted-foreground">
      <p>
        Review-canon §3: every behavioral PR carries a mermaid <code className="text-foreground">sequenceDiagram</code>,{" "}
        <code className="text-foreground">flowchart</code>, or{" "}
        <code className="text-foreground">stateDiagram</code> of what the PR does, rendered with{" "}
        <code className="text-foreground">mmdc</code> for review. Pure docs/config may mark n/a.
      </p>
      <pre className="overflow-x-auto rounded-2xl border border-border bg-card/60 p-4 font-mono text-xs text-foreground">
        {`sequenceDiagram
    participant Human
    participant UI as Headed UI
    participant Plane as App Control
    participant Model as AppModel
    Human->>UI: click
    UI->>Model: same method
    Plane->>Model: POST /action
    Model-->>Plane: state
    Plane-->>Human: GET /state + screenshot`}
      </pre>
    </div>
  )
}
