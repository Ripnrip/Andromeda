import Image from "next/image"
import { PILLARS } from "@/lib/pillars"

/**
 * Wide banner for the top of a GitHub README (1280 x 400 export target).
 * Rendered at a fixed width so it screenshots cleanly to a PNG.
 */
export function ReadmeBanner() {
  return (
    <div
      className="relative overflow-hidden bg-starfield"
      style={{
        width: 1280,
        height: 400,
        background: "radial-gradient(120% 140% at 50% 120%, oklch(0.24 0.06 195), oklch(0.13 0.02 210) 60%)",
      }}
    >
      {/* horizon glow */}
      <div
        aria-hidden
        className="absolute inset-x-0 bottom-0 h-px"
        style={{ background: "oklch(0.83 0.14 190)", boxShadow: "0 0 60px 8px oklch(0.83 0.14 190 / 0.6)" }}
      />
      <div
        aria-hidden
        className="absolute -bottom-40 left-1/2 h-80 w-[140%] -translate-x-1/2 rounded-[50%]"
        style={{ border: "1px solid oklch(0.83 0.14 190 / 0.4)", boxShadow: "0 0 80px oklch(0.83 0.14 190 / 0.25)" }}
      />

      <div className="relative flex h-full items-center gap-10 px-16">
        <div className="relative shrink-0">
          <div
            aria-hidden
            className="absolute inset-0 rounded-full"
            style={{ background: "radial-gradient(circle, oklch(0.83 0.14 190 / 0.5), transparent 70%)", filter: "blur(24px)" }}
          />
          <Image
            src="/andromeda-icon.png"
            alt="Andromeda"
            width={200}
            height={200}
            className="relative rounded-[22%] object-cover"
            priority
          />
        </div>

        <div className="min-w-0">
          <div className="mb-3 flex items-center gap-3">
            <span className="h-px w-8 bg-primary/60" />
            <span className="font-mono text-sm uppercase tracking-[0.4em] text-primary">Control Plane</span>
          </div>
          <h1 className="font-sans text-7xl font-bold tracking-tight text-foreground">Andromeda</h1>
          <p className="mt-3 max-w-xl text-pretty text-lg leading-relaxed text-muted-foreground">
            A macOS-first, Swift-native control plane for visible, durable, graph-aware multi-agent engineering.
          </p>
          <div className="mt-6 flex flex-wrap gap-2">
            {PILLARS.map((p) => (
              <span
                key={p.key}
                className="flex items-center gap-2 rounded-full border border-border bg-card/60 px-3 py-1.5 font-mono text-xs text-foreground"
              >
                <p.icon className="h-3.5 w-3.5 text-primary" />
                {p.name}
              </span>
            ))}
          </div>
        </div>
      </div>
    </div>
  )
}
