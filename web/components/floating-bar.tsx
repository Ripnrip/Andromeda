"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import { Grip, Minus, Rotate3d, X } from "lucide-react"
import { PILLARS, STATUS_LABEL, type Pillar } from "@/lib/pillars"

type Orientation = "horizontal" | "vertical"

const STATUS_COLOR = {
  shipped: "var(--shipped)",
  partial: "var(--partial)",
  spec: "var(--spec)",
} as const

export function FloatingBar({
  initialOrientation = "horizontal",
  initial = { x: 24, y: 24 },
  boundsRef,
  onOrientationChange,
}: {
  initialOrientation?: Orientation
  initial?: { x: number; y: number }
  boundsRef?: React.RefObject<HTMLElement | null>
  onOrientationChange?: (o: Orientation) => void
}) {
  const [orientation, setOrientation] = useState<Orientation>(initialOrientation)
  const [pos, setPos] = useState(initial)
  const [active, setActive] = useState<string>("memory")
  const [minimized, setMinimized] = useState(false)
  const barRef = useRef<HTMLDivElement>(null)
  const drag = useRef<{ dx: number; dy: number } | null>(null)

  const clamp = useCallback(
    (x: number, y: number) => {
      const bounds = boundsRef?.current?.getBoundingClientRect()
      const bar = barRef.current?.getBoundingClientRect()
      if (!bounds || !bar) return { x, y }
      const maxX = bounds.width - bar.width
      const maxY = bounds.height - bar.height
      return {
        x: Math.min(Math.max(0, x), Math.max(0, maxX)),
        y: Math.min(Math.max(0, y), Math.max(0, maxY)),
      }
    },
    [boundsRef],
  )

  const onPointerDown = (e: React.PointerEvent) => {
    const bounds = boundsRef?.current?.getBoundingClientRect()
    if (!bounds) return
    drag.current = {
      dx: e.clientX - bounds.left - pos.x,
      dy: e.clientY - bounds.top - pos.y,
    }
    ;(e.target as HTMLElement).setPointerCapture(e.pointerId)
  }

  const onPointerMove = (e: React.PointerEvent) => {
    if (!drag.current) return
    const bounds = boundsRef?.current?.getBoundingClientRect()
    if (!bounds) return
    const next = clamp(e.clientX - bounds.left - drag.current.dx, e.clientY - bounds.top - drag.current.dy)
    setPos(next)
  }

  const onPointerUp = (e: React.PointerEvent) => {
    drag.current = null
    ;(e.target as HTMLElement).releasePointerCapture?.(e.pointerId)
  }

  const toggleOrientation = () => {
    setOrientation((o) => {
      const next = o === "horizontal" ? "vertical" : "horizontal"
      onOrientationChange?.(next)
      return next
    })
  }

  useEffect(() => {
    setPos((p) => clamp(p.x, p.y))
  }, [orientation, minimized, clamp])

  const isH = orientation === "horizontal"

  return (
    <div ref={barRef} className="absolute z-20 select-none" style={{ left: pos.x, top: pos.y, touchAction: "none" }}>
      <div
        className={[
          "flex items-center gap-1.5 border border-border/70 bg-popover/80 p-1.5 backdrop-blur-xl",
          "rounded-full ring-1 ring-primary/10 shadow-[0_24px_70px_-20px_oklch(0.05_0.02_210/0.95)]",
          isH ? "flex-row" : "flex-col",
        ].join(" ")}
      >
        {/* Grip handle */}
        <button
          aria-label="Drag Andromeda bar"
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={onPointerUp}
          className="flex h-9 w-9 shrink-0 cursor-grab items-center justify-center rounded-full text-muted-foreground/70 transition-colors hover:text-foreground active:cursor-grabbing"
        >
          <Grip className="h-4 w-4" strokeWidth={1.75} />
        </button>

        {/* Orbital core — the living center */}
        <OrbitalCore />

        {isH && !minimized && (
          <input
            type="text"
            placeholder="recall, store, journal…"
            aria-label="Command Andromeda"
            className="h-9 w-36 rounded-full bg-transparent px-2 font-serif text-[15px] italic text-foreground/90 placeholder:text-muted-foreground/70 outline-none transition-[width] duration-300 focus:w-56"
          />
        )}

        {!minimized && (
          <>
            <div className={isH ? "mx-0.5 h-6 w-px bg-border/70" : "my-0.5 h-px w-6 bg-border/70"} aria-hidden />
            <div
              className={["flex items-center gap-0.5", isH ? "flex-row" : "flex-col"].join(" ")}
              role="toolbar"
              aria-label="Andromeda pillars"
            >
              {PILLARS.map((p) => (
                <PillarButton
                  key={p.key}
                  pillar={p}
                  active={active === p.key}
                  onClick={() => setActive(p.key)}
                  horizontal={isH}
                />
              ))}
            </div>
            <div className={isH ? "mx-0.5 h-6 w-px bg-border/70" : "my-0.5 h-px w-6 bg-border/70"} aria-hidden />
            <FleetPill horizontal={isH} />
          </>
        )}

        {/* Controls */}
        <div className={["flex items-center gap-0.5", isH ? "flex-row" : "flex-col"].join(" ")}>
          <ControlButton label="Rotate bar" onClick={toggleOrientation}>
            <Rotate3d className="h-4 w-4" strokeWidth={1.75} />
          </ControlButton>
          <ControlButton label={minimized ? "Expand" : "Minimize"} onClick={() => setMinimized((m) => !m)}>
            <Minus className="h-4 w-4" strokeWidth={1.75} />
          </ControlButton>
          <ControlButton label="Close (demo)" onClick={() => {}}>
            <X className="h-4 w-4" strokeWidth={1.75} />
          </ControlButton>
        </div>
      </div>
    </div>
  )
}

function OrbitalCore() {
  return (
    <span className="relative flex h-9 w-9 shrink-0 items-center justify-center" aria-hidden>
      <span className="absolute h-7 w-7 rounded-full border border-primary/25 animate-drift" />
      <span className="absolute left-1 top-1/2 h-1 w-1 -translate-y-1/2 rounded-full bg-primary/50" />
      <span className="h-2.5 w-2.5 rounded-full bg-primary animate-orbital" />
    </span>
  )
}

function FleetPill({ horizontal }: { horizontal: boolean }) {
  return (
    <span
      className="flex shrink-0 items-center gap-1.5 rounded-full border border-[var(--signal)]/30 bg-[var(--signal)]/12 px-2.5 py-1.5"
      title="Fleet — 12 of 12 daemons GREEN"
    >
      <span className="h-1.5 w-1.5 rounded-full bg-[var(--signal)] shadow-[0_0_6px_var(--signal)]" />
      {horizontal && <span className="font-mono text-[11px] text-[var(--signal)]">12/12</span>}
    </span>
  )
}

function PillarButton({
  pillar,
  active,
  onClick,
  horizontal,
}: {
  pillar: Pillar
  active: boolean
  onClick: () => void
  horizontal: boolean
}) {
  const Icon = pillar.icon
  return (
    <button
      onClick={onClick}
      title={`${pillar.name} — ${STATUS_LABEL[pillar.status]}`}
      aria-pressed={active}
      className={[
        "group relative flex h-9 w-9 items-center justify-center rounded-full transition-all",
        active
          ? "bg-primary/15 text-primary ring-1 ring-primary/40"
          : "text-muted-foreground hover:bg-secondary/70 hover:text-foreground",
      ].join(" ")}
    >
      <Icon className="h-[18px] w-[18px]" strokeWidth={1.5} />
      <span
        className="absolute h-1.5 w-1.5 rounded-full"
        style={{
          backgroundColor: STATUS_COLOR[pillar.status],
          top: 5,
          right: 5,
          boxShadow: active ? `0 0 6px ${STATUS_COLOR[pillar.status]}` : "none",
        }}
        aria-hidden
      />
      <span
        className={[
          "pointer-events-none absolute z-30 flex items-center gap-1.5 whitespace-nowrap rounded-md border border-border bg-popover px-2 py-1 opacity-0 shadow-lg transition-opacity group-hover:opacity-100",
          horizontal ? "top-full mt-2 left-1/2 -translate-x-1/2" : "left-full ml-2 top-1/2 -translate-y-1/2",
        ].join(" ")}
      >
        <span className="font-mono text-[10px] uppercase tracking-widest text-muted-foreground">
          {String(pillar.index).padStart(2, "0")}
        </span>
        <span className="text-xs font-medium text-foreground">{pillar.name}</span>
        <span className="font-mono text-[10px] text-primary">{pillar.capabilities[0]}</span>
      </span>
    </button>
  )
}

function ControlButton({
  children,
  label,
  onClick,
}: {
  children: React.ReactNode
  label: string
  onClick: () => void
}) {
  return (
    <button
      onClick={onClick}
      aria-label={label}
      title={label}
      className="flex h-9 w-9 items-center justify-center rounded-full text-muted-foreground/70 transition-colors hover:bg-secondary/70 hover:text-foreground"
    >
      {children}
    </button>
  )
}
