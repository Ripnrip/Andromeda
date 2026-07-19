import Link from "next/link"
import { AndromedaMark } from "./andromeda-mark"

export function SiteFooter() {
  return (
    <footer className="border-t border-border/60 py-12">
      <div className="mx-auto flex max-w-6xl flex-col items-start justify-between gap-6 px-6 md:flex-row md:items-center">
        <div className="flex items-center gap-3">
          <AndromedaMark size={28} />
          <div>
            <p className="font-semibold">Andromeda</p>
            <p className="font-mono text-xs text-muted-foreground">Six pillars. One curtain. No silent sprawl.</p>
          </div>
        </div>
        <div className="flex items-center gap-5 text-sm text-muted-foreground">
          <Link href="/design" className="transition-colors hover:text-foreground">
            Design System
          </Link>
          <Link href="/banner" className="transition-colors hover:text-foreground">
            Banner
          </Link>
          <Link href="https://github.com/Ripnrip/Andromeda" className="transition-colors hover:text-foreground">
            GitHub
          </Link>
        </div>
      </div>
    </footer>
  )
}
