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
            <p className="font-mono text-xs text-muted-foreground">
              Work in progress · building Memory first · no silent sprawl.
            </p>
          </div>
        </div>
        <div className="flex items-center gap-5 text-sm text-muted-foreground">
          <Link href="#memory" className="transition-colors hover:text-foreground">
            Memory
          </Link>
          <Link href="#roadmap" className="transition-colors hover:text-foreground">
            Roadmap
          </Link>
          <Link href="#waitlist" className="transition-colors hover:text-foreground">
            Request access
          </Link>
        </div>
      </div>
    </footer>
  )
}
