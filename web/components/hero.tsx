import Image from "next/image"
import Link from "next/link"
import { ArrowRight, Terminal } from "lucide-react"
import { MISSION_LOOP } from "@/lib/pillars"

export function Hero() {
  return (
    <section className="relative overflow-hidden">
      {/* Atmosphere */}
      <div aria-hidden className="pointer-events-none absolute inset-0 bg-starfield opacity-70" />
      <div
        aria-hidden
        className="pointer-events-none absolute inset-x-0 top-0 h-[560px]"
        style={{
          background:
            "radial-gradient(60% 50% at 50% 0%, oklch(0.3 0.08 195 / 0.5), transparent 70%)",
        }}
      />

      <div className="relative mx-auto max-w-6xl px-6 pb-20 pt-20 md:pt-28">
        <div className="grid items-center gap-12 md:grid-cols-2">
          <div>
            <div className="mb-5 inline-flex items-center gap-2 rounded-full border border-border bg-card/60 px-3 py-1.5 font-mono text-xs text-muted-foreground">
              <span className="h-1.5 w-1.5 rounded-full bg-primary" style={{ boxShadow: "0 0 8px var(--primary)" }} />
              Observe → Evolve → Execute → Internalize
            </div>
            <h1 className="text-balance font-serif text-6xl leading-[1.02] tracking-tight md:text-7xl">
              The control plane for{" "}
              <span className="italic text-primary" style={{ textShadow: "0 0 40px oklch(0.83 0.14 190 / 0.4)" }}>
                multi-agent
              </span>{" "}
              engineering
            </h1>
            <p className="mt-6 max-w-xl text-pretty text-lg leading-relaxed text-muted-foreground">
              The local-first Swift control plane — <span className="font-serif italic text-foreground/90">visible,
              durable, graph-aware</span>. One observable, permission-aware system in place of fragile scripts,
              hidden workers, and provider-specific wiring.
            </p>
            <div className="mt-8 flex flex-wrap items-center gap-3">
              <Link
                href="#pillars"
                className="group inline-flex items-center gap-2 rounded-xl bg-primary px-5 py-3 font-medium text-primary-foreground transition-transform hover:scale-[1.02]"
                style={{ boxShadow: "0 8px 30px oklch(0.83 0.14 190 / 0.3)" }}
              >
                Explore the six pillars
                <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-0.5" />
              </Link>
              <Link
                href="#bar"
                className="inline-flex items-center gap-2 rounded-xl border border-border bg-card px-5 py-3 font-medium text-foreground transition-colors hover:border-primary/50"
              >
                <Terminal className="h-4 w-4 text-primary" />
                Try the command bar
              </Link>
            </div>

            {/* Quick start */}
            <div className="mt-8 rounded-xl border border-border bg-card/60 p-4 font-mono text-sm">
              <div className="mb-2 flex items-center gap-1.5">
                <span className="h-2.5 w-2.5 rounded-full bg-partial/70" />
                <span className="h-2.5 w-2.5 rounded-full bg-muted-foreground/40" />
                <span className="h-2.5 w-2.5 rounded-full bg-primary/60" />
                <span className="ml-2 text-xs text-muted-foreground">andromeda — zsh</span>
              </div>
              <p className="text-muted-foreground">
                <span className="text-primary">$</span> swift run andromeda serve --port 8080
              </p>
              <p className="text-muted-foreground/70">
                <span className="text-primary">→</span> gateway live · X-Autocache-ROI-Percent: 41%
              </p>
            </div>
          </div>

          {/* Logo art */}
          <div className="relative flex items-center justify-center">
            <div
              aria-hidden
              className="absolute h-72 w-72 rounded-full"
              style={{
                background: "radial-gradient(circle, oklch(0.83 0.14 190 / 0.35), transparent 65%)",
                filter: "blur(30px)",
              }}
            />
            <div
              className="relative overflow-hidden rounded-2xl border border-border"
              style={{ boxShadow: "0 30px 80px oklch(0.72 0.14 190 / 0.2)" }}
            >
              <Image
                src="/andromeda-hero.png"
                alt="Andromeda — a glowing trefoil rising over a dark horizon beneath a constellation"
                width={720}
                height={405}
                className="relative object-cover"
                priority
              />
              <div
                aria-hidden
                className="pointer-events-none absolute inset-0"
                style={{ boxShadow: "inset 0 0 60px oklch(0 0 0 / 0.5)" }}
              />
            </div>
          </div>
        </div>

        {/* Mission loop */}
        <div className="mt-16 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          {MISSION_LOOP.map((m, i) => (
            <div key={m.stage} className="rounded-xl border border-border bg-card/50 p-4">
              <div className="flex items-center gap-2">
                <span className="font-mono text-xs text-primary">{String(i + 1).padStart(2, "0")}</span>
                <span className="font-semibold">{m.stage}</span>
              </div>
              <p className="mt-1.5 text-sm leading-relaxed text-muted-foreground">{m.detail}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
