"use client"

import { useState } from "react"
import { SignalHigh } from "lucide-react"

export function DynamicIsland() {
  const [expanded, setExpanded] = useState(false)

  return (
    <div className="flex flex-col items-center gap-4">
      <button
        onClick={() => setExpanded((v) => !v)}
        aria-expanded={expanded}
        aria-label={expanded ? "Collapse live activity" : "Expand live activity"}
        className={[
          "group overflow-hidden bg-black text-left text-foreground ring-1 ring-white/10 transition-all duration-500 ease-out",
          expanded
            ? "w-[380px] rounded-[28px] p-4 shadow-[0_30px_80px_-20px_oklch(0.05_0.02_210)]"
            : "flex h-11 w-[300px] items-center gap-3 rounded-full px-4",
        ].join(" ")}
      >
        {expanded ? <IslandExpanded /> : <IslandIdle />}
      </button>
      <p className="font-serif text-sm italic text-muted-foreground">
        {expanded ? "write.tool is live — click to collapse to the notch" : "Ambient pulse lives at the notch — click to peek"}
      </p>
    </div>
  )
}

function IslandIdle() {
  return (
    <>
      <span className="font-serif text-[15px] italic text-foreground/90">Andromeda</span>
      <span className="ml-auto flex items-center gap-1.5">
        <span className="relative flex h-2 w-2">
          <span className="absolute inline-flex h-full w-full rounded-full bg-[var(--signal)] opacity-75 animate-orbital" />
          <span className="relative inline-flex h-2 w-2 rounded-full bg-[var(--signal)]" />
        </span>
        <SignalHigh className="h-4 w-4 text-[var(--signal)]" strokeWidth={2} />
        <span className="font-mono text-xs tracking-wide text-[var(--signal)]">GREEN</span>
      </span>
      <span className="ml-2 font-mono text-[11px] text-muted-foreground">⌘⇧Space</span>
    </>
  )
}

function IslandExpanded() {
  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-start gap-3">
        <span className="relative mt-1 flex h-2.5 w-2.5 shrink-0">
          <span className="absolute inline-flex h-full w-full rounded-full bg-primary opacity-70 animate-orbital" />
          <span className="relative inline-flex h-2.5 w-2.5 rounded-full bg-primary" />
        </span>
        <div className="min-w-0 flex-1">
          <div className="flex items-baseline justify-between gap-2">
            <span className="font-mono text-sm text-primary">write.tool</span>
            <span className="font-mono text-xs text-muted-foreground">2.1s</span>
          </div>
          <p className="font-serif text-[15px] italic text-foreground/80">Capturing session thought…</p>
        </div>
      </div>

      {/* progress */}
      <div className="h-1 w-full overflow-hidden rounded-full bg-white/10">
        <div className="h-full w-[62%] rounded-full bg-primary animate-orbital" />
      </div>

      <div className="flex flex-wrap items-center gap-1.5">
        <Chip>
          <span className="h-1.5 w-1.5 rounded-full bg-[var(--signal)]" /> fleet 12/12
        </Chip>
        <Chip>visibility: private</Chip>
        <Chip>curtain ✓</Chip>
      </div>
    </div>
  )
}

function Chip({ children }: { children: React.ReactNode }) {
  return (
    <span className="flex items-center gap-1.5 rounded-full bg-white/8 px-2.5 py-1 font-mono text-[11px] text-foreground/80">
      {children}
    </span>
  )
}
