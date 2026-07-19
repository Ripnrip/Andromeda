"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import { GripVertical, GripHorizontal, Minus, RotateCcw, X, Activity } from "lucide-react"
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

  // Re-clamp when orientation changes size
  useEffect(() => {
    setPos((p) => clamp(p.x, p.y))
  }, [orientation, minimized, clamp])

  const isH = orientation === "horizontal"

  return (
    <div
      ref={barRef}
      className="absolute z-20 select-none"
      style={{ left: pos.x, top: pos.y, touchAction: "none" }}
    >
      <div
        className={[
          "flex items-stretch gap-1 rounded-2xl border border-border/80 bg-popover/85 p-1.5 shadow-2xl backdrop-blur-xl",
          "shadow-[0_20px_60px_-15px_oklch(0.05_0.02_210/0.9)] ring-1 ring-primary/10",
          isH ? "flex-row" : "flex-col",
        ].join(" ")}
      >
        {/* Grip handle */}
        <button
          aria-label="Drag Andromeda bar"
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={onPointerUp}
          className={[
            "flex cursor-grab items-center justify-center rounded-lg text-muted-foreground transition-colors hover:bg-secondary hover:text-foreground active:cursor-grabbing",
            isH ? "px-1 py-2" : "px-2 py-1",
          ].join(" ")}
        >
          {isH ? <GripVertical className="h-4 w-4" /> : <GripHorizontal className="h-4 w-4" />}
        </button>

        {!minimized && (
          <>
            <div className={isH ? "my-1 w-px bg-border" : "mx-1 h-px bg-border"} aria-hidden />

            {/* Pillars */}
            <div className={["flex gap-0.5", isH ? "flex-row" : "flex-col"].join(" ")} role="toolbar" aria-label="Andromeda pillars">
              {PILLARS.map((p) => (
                <PillarButton key={p.key} pillar={p} active={active === p.key} onClick={() => setActive(p.key)} horizontal={isH} />
              ))}
            </div>

            <div className={isH ? "my-1 w-px bg-border" : "mx-1 h-px bg-border"} aria-hidden />
          </>
        )}

        {/* Controls */}
        <div className={["flex gap-0.5", isH ? "flex-row" : "flex-col"].join(" ")}>
          <ControlButton label="Rotate bar" onClick={toggleOrientation}>
            <RotateCcw className="h-4 w-4" />
          </ControlButton>
          <ControlButton label={minimized ? "Expand" : "Minimize"} onClick={() => setMinimized((m) => !m)}>
            {minimized ? <Activity className="h-4 w-4" /> : <Minus className="h-4 w-4" />}
          </ControlButton>
          <ControlButton label="Close (demo)" onClick={() => {}} danger>
            <X className="h-4 w-4" />
          </ControlButton>
        </div>
      </div>

      {/* Active capability readout */}
      {!minimized && <ActiveReadout activeKey={active} horizontal={isH} />}
    </div>
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
        "group relative flex h-10 w-10 items-center justify-center rounded-lg transition-all",
        active
          ? "bg-primary/15 text-primary ring-1 ring-primary/40"
          : "text-muted-foreground hover:bg-secondary hover:text-foreground",
      ].join(" ")}
    >
      <Icon className="h-[18px] w-[18px]" />
      <span
        className="absolute h-1.5 w-1.5 rounded-full"
        style={{
          backgroundColor: STATUS_COLOR[pillar.status],
          top: 4,
          right: 4,
          boxShadow: active ? `0 0 6px ${STATUS_COLOR[pillar.status]}` : "none",
        }}
        aria-hidden
      />
      {/* Tooltip */}
      <span
        className={[
          "pointer-events-none absolute z-30 whitespace-nowrap rounded-md border border-border bg-popover px-2 py-1 font-mono text-[10px] uppercase tracking-wider text-foreground opacity-0 shadow-lg transition-opacity group-hover:opacity-100",
          horizontal ? "top-full mt-2 left-1/2 -translate-x-1/2" : "left-full ml-2 top-1/2 -translate-y-1/2",
        ].join(" ")}
      >
        {pillar.name}
      </span>
    </button>
  )
}

function ControlButton({
  children,
  label,
  onClick,
  danger,
}: {
  children: React.ReactNode
  label: string
  onClick: () => void
  danger?: boolean
}) {
  return (
    <button
      onClick={onClick}
      aria-label={label}
      title={label}
      className={[
        "flex h-10 w-9 items-center justify-center rounded-lg text-muted-foreground transition-colors",
        danger ? "hover:bg-secondary hover:text-foreground" : "hover:bg-secondary hover:text-foreground",
      ].join(" ")}
    >
      {children}
    </button>
  )
}

function ActiveReadout({ activeKey, horizontal }: { activeKey: string; horizontal: boolean }) {
  const pillar = PILLARS.find((p) => p.key === activeKey)
  if (!pillar) return null
  return (
    <div
      className={[
        "absolute rounded-xl border border-border/80 bg-popover/85 px-3 py-2 shadow-xl backdrop-blur-xl",
        horizontal ? "left-0 top-full mt-2" : "left-full top-0 ml-2",
      ].join(" ")}
      style={{ minWidth: 180 }}
    >
      <div className="flex items-center gap-2">
        <span className="font-mono text-[10px] uppercase tracking-widest text-muted-foreground">
          {String(pillar.index).padStart(2, "0")}
        </span>
        <span className="text-sm font-semibold text-foreground">{pillar.name}</span>
      </div>
      <p className="mt-0.5 font-mono text-[11px] text-primary">{pillar.capabilities[0]}</p>
    </div>
  )
}
