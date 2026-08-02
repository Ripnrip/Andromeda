import Image from "next/image"
import Link from "next/link"
import { ArrowUpRight, Github, Moon, Users } from "lucide-react"

const FOUNDERS = [
  {
    name: "Gurinder Singh",
    handle: "@Ripnrip",
    href: "https://github.com/Ripnrip",
    image: "/founders/gurinder-full.png",
    alt: "Full illustrated portrait of Gurinder Singh at an arcade",
    frameClass: "aspect-square",
    imageClass: "object-cover object-center",
  },
  {
    name: "@hashimotolabs",
    handle: "GitHub",
    href: "https://github.com/hashimotolabs",
    image: "/founders/hashimotolabs.png",
    alt: "Portrait of the Hashimoto Labs founder in a terminal-filled workspace",
    frameClass: "aspect-square",
    imageClass: "object-cover object-top",
  },
] as const

export function FounderStory() {
  return (
    <section id="story" className="relative overflow-hidden border-t border-border/60 py-20 md:py-28">
      <div className="mx-auto max-w-6xl px-6">
        <div className="grid gap-12 lg:grid-cols-[0.9fr_1.1fr] lg:items-start">
          <div className="lg:sticky lg:top-28">
            <p className="font-mono text-xs uppercase tracking-[0.3em] text-primary">Why we&apos;re building it</p>
            <h2 className="mt-4 max-w-xl text-balance font-serif text-4xl leading-[1.05] tracking-tight md:text-6xl">
              Two old friends. Too many late nights. The same problems, over and over.
            </h2>
            <p className="mt-6 max-w-xl text-pretty text-base leading-relaxed text-muted-foreground md:text-lg">
              We grew up together, took different paths through college, then found our way back to each other through
              code. Pair coding after work started as the thing we did for the love of it. Before long, every night
              exposed another piece of infrastructure that should have been simpler.
            </p>
          </div>

          <div className="flex flex-col gap-6">
            <div className="rounded-2xl border border-border bg-card/60 p-6 md:p-8">
              <div className="flex items-center gap-3 font-mono text-xs uppercase tracking-[0.24em] text-primary">
                <Moon className="size-4" aria-hidden="true" />
                The nights that became a roadmap
              </div>
              <div className="mt-6 flex flex-col gap-5 text-base leading-relaxed text-muted-foreground">
                <p>
                  Our agents forgot yesterday&apos;s work. Environment secrets sprawled across machines. JavaScript and
                  Node dependencies had to be overridden just to make tools fit the way we worked. Even a Cerebras
                  floor rug became one more oddly specific problem we had to solve. We kept building one-off fixes,
                  wrappers, and small automations because making things together was the point &mdash; not babysitting,
                  handholding, or micromanaging brittle peripheral infrastructure.
                </p>
                <p>
                  Eventually the pattern was impossible to miss: forgotten context, tool and process sprawl, buried
                  skills, provider churn, scattered secrets, and invisible automation were not isolated annoyances.
                  They were parts of the same missing control plane. We started solving it for ourselves, chose Memory
                  as the first active build track, and turned those nightly fixes into the six-pillar charter you see
                  here.
                </p>
              </div>
              <div className="mt-8 flex items-start gap-3 border-t border-border/60 pt-6">
                <Users className="mt-0.5 size-5 shrink-0 text-primary" aria-hidden="true" />
                <p className="text-pretty font-serif text-xl italic leading-relaxed text-foreground">
                  Now we want to bring it to the community: built in the open, shaped by real use, and released for the
                  open-source world that taught us how to build.
                </p>
              </div>
            </div>

            <div className="grid items-start gap-4 sm:grid-cols-2">
              {FOUNDERS.map((founder) => (
                <Link
                  key={founder.href}
                  href={founder.href}
                  target="_blank"
                  rel="noreferrer"
                  className="group overflow-hidden rounded-2xl border border-border bg-card/40 transition-colors hover:border-primary/40"
                >
                  <div
                    className={`relative overflow-hidden border-b border-border/60 bg-secondary ${founder.frameClass}`}
                    style={{ position: "relative", overflow: "hidden", aspectRatio: "1 / 1" }}
                  >
                    <Image
                      src={founder.image}
                      alt={founder.alt}
                      fill
                      sizes="(min-width: 640px) 280px, 100vw"
                      className={`${founder.imageClass} transition-transform duration-500 group-hover:brightness-110`}
                    />
                  </div>
                  <div className="flex items-center justify-between gap-4 p-5">
                    <div>
                      <p className="font-semibold text-foreground">{founder.name}</p>
                      <p className="mt-1 flex items-center gap-1.5 font-mono text-xs text-muted-foreground">
                        <Github className="size-3.5" aria-hidden="true" />
                        {founder.handle}
                      </p>
                    </div>
                    <ArrowUpRight className="size-5 text-muted-foreground transition-colors group-hover:text-primary" aria-hidden="true" />
                  </div>
                </Link>
              ))}
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
