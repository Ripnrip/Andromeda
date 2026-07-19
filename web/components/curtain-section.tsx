import { CURTAIN } from "@/lib/pillars"
import { SectionHeading } from "./pillars-section"
import { EyeOff } from "lucide-react"

export function CurtainSection() {
  return (
    <section id="curtain" className="relative border-t border-border/60 py-20">
      <div className="mx-auto max-w-6xl px-6">
        <SectionHeading
          eyebrow="Capability curtain"
          title="Stable ID in, resolved provider out"
          desc="Client menus expose stable capability IDs only — never tracker names, provider brands, or raw env keys. The broker injects secrets server-side at call time."
        />

        <div className="mt-12 overflow-hidden rounded-2xl border border-border bg-card/40">
          {/* Header */}
          <div className="grid grid-cols-12 gap-4 border-b border-border bg-secondary/50 px-5 py-3 font-mono text-[11px] uppercase tracking-wider text-muted-foreground">
            <div className="col-span-3">Capability ID</div>
            <div className="col-span-5">Hides behind the curtain</div>
            <div className="col-span-4">Client must never see</div>
          </div>
          {CURTAIN.map((row) => (
            <div
              key={row.id}
              className="grid grid-cols-12 items-center gap-4 border-b border-border/50 px-5 py-4 text-sm transition-colors last:border-0 hover:bg-secondary/30"
            >
              <div className="col-span-3">
                <code className="rounded-md bg-primary/10 px-2 py-1 font-mono text-[12px] text-primary">
                  {row.id}
                </code>
              </div>
              <div className="col-span-5 text-muted-foreground">{row.hides}</div>
              <div className="col-span-4 flex items-center gap-2 text-muted-foreground/80">
                <EyeOff className="h-3.5 w-3.5 shrink-0 text-partial" />
                <span className="line-through decoration-partial/40">{row.neverSees}</span>
              </div>
            </div>
          ))}
        </div>

        <p className="mt-6 flex items-center gap-2 font-mono text-xs text-muted-foreground">
          <span className="text-primary">hard rule</span>
          UI LaunchAgents and satellite agents run env-scrubbed (HOME + PATH only).
        </p>
      </div>
    </section>
  )
}
