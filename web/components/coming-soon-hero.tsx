import Image from "next/image"
import Link from "next/link"
import { ArrowRight, Brain } from "lucide-react"

export function ComingSoonHero() {
  return (
    <section className="relative overflow-hidden">
      <div aria-hidden className="pointer-events-none absolute inset-0 bg-starfield opacity-70" />
      <div
        aria-hidden
        className="pointer-events-none absolute inset-x-0 top-0 h-[560px]"
        style={{
          background: "radial-gradient(60% 50% at 50% 0%, oklch(0.3 0.08 195 / 0.5), transparent 70%)",
        }}
      />

      <div className="relative mx-auto max-w-6xl px-6 pb-20 pt-20 md:pt-28">
        <div className="grid items-center gap-12 md:grid-cols-2">
          <div>
            <div className="mb-5 inline-flex items-center gap-2 rounded-full border border-border bg-card/60 px-3 py-1.5 font-mono text-xs text-muted-foreground">
              <span
                className="h-1.5 w-1.5 rounded-full bg-partial"
                style={{ boxShadow: "0 0 8px var(--partial)" }}
              />
              Work in progress · building in the open
            </div>

            <h1 className="text-balance font-serif text-6xl leading-[1.02] tracking-tight md:text-7xl">
              One connected{" "}
              <span className="italic text-primary" style={{ textShadow: "0 0 40px oklch(0.83 0.14 190 / 0.4)" }}>
                brain
              </span>{" "}
              for everything your agents learn
            </h1>

            <p className="mt-6 max-w-xl text-pretty text-lg leading-relaxed text-muted-foreground">
              Every agent you run generates a river of work each day — fixes, decisions, root causes — and without
              memory it all evaporates. <span className="font-serif italic text-foreground/90">Andromeda</span> is a
              local-first Swift control plane whose first pillar, <span className="text-foreground">Anima</span>,
              distills every agent&apos;s day into one curated, connected, queryable brain.
            </p>

            <div className="mt-8 flex flex-wrap items-center gap-3">
              <Link
                href="#waitlist"
                className="group inline-flex items-center gap-2 rounded-xl bg-primary px-5 py-3 font-medium text-primary-foreground transition-transform hover:scale-[1.02]"
                style={{ boxShadow: "0 8px 30px oklch(0.83 0.14 190 / 0.3)" }}
              >
                Request early access
                <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-0.5" />
              </Link>
              <Link
                href="#memory"
                className="inline-flex items-center gap-2 rounded-xl border border-border bg-card px-5 py-3 font-medium text-foreground transition-colors hover:border-primary/50"
              >
                <Brain className="h-4 w-4 text-primary" />
                See what we&apos;re building
              </Link>
            </div>

            <p className="mt-6 font-mono text-xs leading-relaxed text-muted-foreground">
              Andromeda is in active development. Memory (Anima) is the pillar we&apos;re building first — the rest of
              the control plane is on the roadmap below.
            </p>
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
      </div>
    </section>
  )
}
