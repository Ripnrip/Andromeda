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
            <h2 className="text-balance text-3xl font-bold tracking-tight md:text-4xl">
              A floating command bar for the fleet
            </h2>
            <p className="mt-4 text-pretty leading-relaxed text-muted-foreground">
              Every background job is observable — nothing runs invisibly. Drag the bar anywhere, rotate it
              between horizontal and vertical, and tap a pillar to surface its capability. This is the visibility
              surface the charter demands.
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
          className="relative mt-10 h-[440px] w-full overflow-hidden rounded-2xl border border-border bg-starfield"
          style={{
            background:
              "radial-gradient(100% 100% at 50% 100%, oklch(0.22 0.05 195 / 0.6), oklch(0.14 0.02 210)), oklch(0.14 0.02 210)",
          }}
        >
          {/* faux desktop grid */}
          <div
            aria-hidden
            className="absolute inset-0 opacity-[0.15]"
            style={{
              backgroundImage:
                "linear-gradient(oklch(0.83 0.14 190 / 0.3) 1px, transparent 1px), linear-gradient(90deg, oklch(0.83 0.14 190 / 0.3) 1px, transparent 1px)",
              backgroundSize: "40px 40px",
            }}
          />
          <div
            aria-hidden
            className="absolute inset-x-0 bottom-0 h-px"
            style={{ background: "oklch(0.83 0.14 190)", boxShadow: "0 0 40px 4px oklch(0.83 0.14 190 / 0.5)" }}
          />

          <FloatingBar boundsRef={canvasRef} initial={{ x: 28, y: 28 }} onOrientationChange={setOrientation} />

          {/* Second instance shown vertically for reference */}
          <FloatingBar boundsRef={canvasRef} initial={{ x: 28, y: 130 }} initialOrientation="vertical" />
        </div>

        <p className="mt-4 font-mono text-xs text-muted-foreground">
          Two live instances — horizontal (top) and vertical. Both fully draggable and rotatable.
        </p>
      </div>
    </section>
  )
}
