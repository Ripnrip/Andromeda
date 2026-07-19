"use client"

import { useRef, useState } from "react"
import { FloatingBar } from "./floating-bar"
import { MousePointer2 } from "lucide-react"

export function BarDemo() {
  const canvasRef = useRef<HTMLDivElement>(null)
  const [orientation, setOrientation] = useState<"horizontal" | "vertical">("horizontal")

  return (
    <section id="bar" className="relative border-t border-border/60 py-20">
      <div className="mx-auto max-w-6xl px-6">
        <div className="mb-3 flex items-center gap-3">
          <span className="h-px w-8 bg-primary/60" />
          <span className="font-mono text-xs uppercase tracking-[0.3em] text-primary">Command bar</span>
        </div>
        <div className="flex flex-wrap items-end justify-between gap-4">
          <div className="max-w-2xl">
            <h2 className="text-balance font-serif text-4xl leading-[1.05] tracking-tight md:text-5xl">
              A living command bar for the fleet
            </h2>
            <p className="mt-4 max-w-xl text-pretty leading-relaxed text-muted-foreground">
              A pulsing core, orbital drift, and a serif command field. Drag it by the grip, rotate between
              horizontal and vertical, and tap a pillar to surface its capability. Every background job stays
              observable — nothing runs invisibly.
            </p>
          </div>
          <div className="flex items-center gap-2 rounded-lg border border-border bg-card px-3 py-2 font-mono text-xs text-muted-foreground">
            <MousePointer2 className="h-3.5 w-3.5 text-primary" />
            Drag the grip · {orientation}
          </div>
        </div>

        {/* Canvas */}
        <div
          ref={canvasRef}
          className="relative mt-10 h-[480px] w-full overflow-hidden rounded-2xl border border-border bg-dotgrid"
          style={{
            backgroundColor: "oklch(0.13 0.018 210)",
          }}
        >
          <div
            aria-hidden
            className="pointer-events-none absolute inset-x-0 bottom-0 h-40"
            style={{ background: "radial-gradient(120% 100% at 50% 100%, oklch(0.22 0.06 195 / 0.45), transparent 70%)" }}
          />
          <div
            aria-hidden
            className="absolute inset-x-0 bottom-0 h-px"
            style={{ background: "oklch(0.83 0.14 190)", boxShadow: "0 0 40px 4px oklch(0.83 0.14 190 / 0.5)" }}
          />

          <FloatingBar boundsRef={canvasRef} initial={{ x: 32, y: 32 }} onOrientationChange={setOrientation} />

          {/* Second instance shown vertically for reference */}
          <FloatingBar boundsRef={canvasRef} initial={{ x: 40, y: 150 }} initialOrientation="vertical" />
        </div>

        <p className="mt-4 font-mono text-xs text-muted-foreground">
          Two live instances — horizontal (top) and vertical. Both fully draggable and rotatable.
        </p>
      </div>
    </section>
  )
}
