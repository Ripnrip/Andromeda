import Link from "next/link"
import { Wordmark } from "./wordmark"

const LINKS = [
  { href: "#memory", label: "Memory" },
  { href: "#recall", label: "Why graph + vector" },
  { href: "#status", label: "Status" },
  { href: "#roadmap", label: "Roadmap" },
]

export function SiteNav() {
  return (
    <header className="sticky top-0 z-50 border-b border-border/60 bg-background/70 backdrop-blur-xl">
      <nav className="mx-auto flex h-16 max-w-6xl items-center justify-between px-6">
        <Link href="/" className="flex items-center gap-2.5">
          <Wordmark size="sm" />
          <span className="hidden rounded-full border border-partial/40 bg-partial/10 px-2 py-0.5 font-mono text-[10px] uppercase tracking-wider text-partial sm:inline">
            Coming soon
          </span>
        </Link>
        <div className="hidden items-center gap-1 md:flex">
          {LINKS.map((l) => (
            <Link
              key={l.href}
              href={l.href}
              className="rounded-lg px-3 py-2 text-sm text-muted-foreground transition-colors hover:bg-secondary hover:text-foreground"
            >
              {l.label}
            </Link>
          ))}
        </div>
        <Link
          href="#waitlist"
          className="rounded-lg bg-primary px-4 py-2 text-sm font-medium text-primary-foreground transition-transform hover:scale-[1.02]"
        >
          Request access
        </Link>
      </nav>
    </header>
  )
}
