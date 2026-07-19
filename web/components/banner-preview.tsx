"use client"

import { useEffect, useRef, useState } from "react"
import Link from "next/link"
import { ReadmeBanner } from "./readme-banner"
import { ArrowUpRight } from "lucide-react"

const W = 1280
const H = 400

export function BannerPreview() {
  const ref = useRef<HTMLDivElement>(null)
  const [scale, setScale] = useState(1)

  useEffect(() => {
    const el = ref.current
    if (!el) return
    const ro = new ResizeObserver(() => setScale(el.clientWidth / W))
    ro.observe(el)
    return () => ro.disconnect()
  }, [])

  return (
    <section className="relative border-t border-border/60 py-20">
      <div className="mx-auto max-w-6xl px-6">
        <div className="mb-3 flex items-center gap-3">
          <span className="h-px w-8 bg-primary/60" />
          <span className="font-mono text-xs uppercase tracking-[0.3em] text-primary">README banner</span>
        </div>
        <div className="flex flex-wrap items-end justify-between gap-4">
          <h2 className="text-balance text-3xl font-bold tracking-tight md:text-4xl">Drop-in repository header</h2>
          <Link
            href="/banner"
            className="inline-flex items-center gap-1.5 rounded-lg border border-border bg-card px-4 py-2 text-sm font-medium transition-colors hover:border-primary/50 hover:text-primary"
          >
            Open full-size <ArrowUpRight className="h-4 w-4" />
          </Link>
        </div>

        <div ref={ref} className="mt-8 overflow-hidden rounded-2xl border border-border" style={{ height: H * scale }}>
          <div className="origin-top-left" style={{ width: W, height: H, transform: `scale(${scale})` }}>
            <ReadmeBanner />
          </div>
        </div>
        <p className="mt-4 font-mono text-xs text-muted-foreground">
          Exported to <span className="text-primary">Documentation/Assets/andromeda-banner.png</span> · 1280 × 400
        </p>
      </div>
    </section>
  )
}
