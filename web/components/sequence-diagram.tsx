"use client"

import { useEffect, useRef, useState } from "react"
import type { SeqDiagram } from "@/lib/memory"

// Column width and row height for the diagram grid
const COL_W = 160
const ROW_H = 48
const HEAD_H = 56
const LIFE_W = 2
const LABEL_FONT = 11

interface Props {
  diagram: SeqDiagram
  /** milliseconds between each step animating in */
  stepDelay?: number
}

export function SequenceDiagram({ diagram, stepDelay = 520 }: Props) {
  const [visibleSteps, setVisibleSteps] = useState(0)
  const [playing, setPlaying] = useState(false)
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  const { participants, steps } = diagram
  const cols = participants.length
  const svgW = cols * COL_W
  const svgH = HEAD_H + steps.length * ROW_H + 32

  // Map participant id → column index
  const colOf = (id: string) => participants.findIndex((p) => p.id === id)
  const cx = (id: string) => colOf(id) * COL_W + COL_W / 2

  function play() {
    setVisibleSteps(0)
    setPlaying(true)
  }

  useEffect(() => {
    if (!playing) return
    if (visibleSteps >= steps.length) {
      setPlaying(false)
      return
    }
    timerRef.current = setTimeout(() => {
      setVisibleSteps((v) => v + 1)
    }, stepDelay)
    return () => { if (timerRef.current) clearTimeout(timerRef.current) }
  }, [playing, visibleSteps, steps.length, stepDelay])

  // Auto-play once on mount
  useEffect(() => { play() }, []) // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <div className="rounded-2xl border border-border bg-card/40 p-4">
      <div className="mb-3 flex items-center justify-between gap-4">
        <div>
          <p className="font-semibold text-sm text-foreground">{diagram.title}</p>
          <p className="text-xs text-muted-foreground">{diagram.subtitle}</p>
        </div>
        <button
          onClick={play}
          aria-label="Replay diagram"
          className="rounded-lg border border-border bg-background/60 px-3 py-1.5 font-mono text-[11px] uppercase tracking-wider text-muted-foreground transition hover:border-primary/40 hover:text-primary"
        >
          replay
        </button>
      </div>

      <div className="overflow-x-auto">
        <svg
          viewBox={`0 0 ${svgW} ${svgH}`}
          width="100%"
          style={{ minWidth: Math.min(svgW, 320) }}
          className="select-none font-mono"
          aria-label={`Sequence diagram: ${diagram.title}`}
        >
          {/* Participant headers */}
          {participants.map((p, i) => {
            const x = i * COL_W + COL_W / 2
            return (
              <g key={p.id}>
                <rect
                  x={x - 56}
                  y={4}
                  width={112}
                  height={40}
                  rx={6}
                  className="fill-secondary stroke-border"
                  strokeWidth={1}
                />
                <text
                  x={x}
                  y={20}
                  textAnchor="middle"
                  dominantBaseline="middle"
                  fontSize={LABEL_FONT}
                  className="fill-foreground"
                  fontWeight={600}
                >
                  {p.label}
                </text>
                {p.sub && (
                  <text
                    x={x}
                    y={35}
                    textAnchor="middle"
                    dominantBaseline="middle"
                    fontSize={9}
                    className="fill-muted-foreground"
                  >
                    {p.sub}
                  </text>
                )}
              </g>
            )
          })}

          {/* Lifelines */}
          {participants.map((p, i) => {
            const x = i * COL_W + COL_W / 2
            return (
              <line
                key={`life-${p.id}`}
                x1={x}
                y1={HEAD_H}
                x2={x}
                y2={svgH - 8}
                strokeWidth={LIFE_W}
                strokeDasharray="4 4"
                className="stroke-border"
              />
            )
          })}

          {/* Steps */}
          {steps.map((step, idx) => {
            const visible = idx < visibleSteps
            if (!visible) return null

            const y = HEAD_H + idx * ROW_H + ROW_H / 2
            const fromX = cx(step.from)
            const toX = cx(step.to)
            const isSelf = step.from === step.to
            const isDashed = step.style === "dashed"
            const isReturn = isDashed

            if (isSelf) {
              // Self-arrow (loopback)
              const lx = fromX + 24
              return (
                <g key={idx} className="animate-fadeIn">
                  <path
                    d={`M ${fromX} ${y - 8} L ${lx} ${y - 8} L ${lx} ${y + 8} L ${fromX} ${y + 8}`}
                    fill="none"
                    strokeWidth={1.5}
                    strokeDasharray={isDashed ? "4 3" : undefined}
                    className="stroke-primary"
                  />
                  <polygon
                    points={`${fromX},${y + 8} ${fromX + 6},${y + 4} ${fromX + 6},${y + 12}`}
                    className="fill-primary"
                  />
                  <text
                    x={lx + 6}
                    y={y}
                    dominantBaseline="middle"
                    fontSize={9}
                    className="fill-muted-foreground"
                  >
                    {step.label}
                  </text>
                </g>
              )
            }

            const goRight = toX > fromX
            const arrowX = toX + (goRight ? -8 : 8)
            const midX = (fromX + toX) / 2

            return (
              <g key={idx}>
                {/* Line */}
                <line
                  x1={fromX}
                  y1={y}
                  x2={arrowX}
                  y2={y}
                  strokeWidth={1.5}
                  strokeDasharray={isDashed ? "5 3" : undefined}
                  className={isReturn ? "stroke-muted-foreground" : "stroke-primary"}
                  style={{ transition: "stroke-dashoffset 0.3s" }}
                />
                {/* Arrowhead */}
                <polygon
                  points={
                    goRight
                      ? `${toX},${y} ${toX - 8},${y - 4} ${toX - 8},${y + 4}`
                      : `${toX},${y} ${toX + 8},${y - 4} ${toX + 8},${y + 4}`
                  }
                  className={isReturn ? "fill-muted-foreground" : "fill-primary"}
                />
                {/* Label */}
                <rect
                  x={midX - 54}
                  y={y - 11}
                  width={108}
                  height={14}
                  rx={3}
                  className="fill-background/80"
                />
                <text
                  x={midX}
                  y={y - 4}
                  textAnchor="middle"
                  dominantBaseline="middle"
                  fontSize={9}
                  className={isReturn ? "fill-muted-foreground" : "fill-foreground"}
                >
                  {step.label}
                </text>
              </g>
            )
          })}

          {/* Note banner at bottom */}
          {diagram.note && visibleSteps >= steps.length && (
            <g>
              <rect
                x={8}
                y={svgH - 22}
                width={svgW - 16}
                height={16}
                rx={4}
                className="fill-primary/10 stroke-primary/20"
                strokeWidth={1}
              />
              <text
                x={svgW / 2}
                y={svgH - 14}
                textAnchor="middle"
                dominantBaseline="middle"
                fontSize={9}
                className="fill-primary"
              >
                {diagram.note}
              </text>
            </g>
          )}
        </svg>
      </div>
    </div>
  )
}
