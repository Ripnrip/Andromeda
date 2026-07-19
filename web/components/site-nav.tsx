import Link from "next/link"
import { Wordmark } from "./wordmark"

const LINKS = [
  { href: "#pillars", label: "Pillars" },
  { href: "#curtain", label: "Curtain" },
  { href: "#bar", label: "Command Bar" },
  { href: "#surfaces", label: "Surfaces" },
  { href: "/design", label: "Design System" },
]

export function SiteNav() {
  return (
    <header className="sticky top-0 z-50 border-b border-border/60 bg-background/70 backdrop-blur-xl">
      <nav className="mx-auto flex h-16 max-w-6xl items-center justify-between px-6">
        <Link href="/" className="flex items-center">
          <Wordmark size="sm" />
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
          href="https://github.com/Ripnrip/Andromeda"
          className="rounded-lg border border-border bg-card px-4 py-2 text-sm font-medium text-foreground transition-colors hover:border-primary/50 hover:text-primary"
        >
          GitHub
        </Link>
      </nav>
    </header>
  )
}
