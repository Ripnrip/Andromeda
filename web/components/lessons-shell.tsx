import Link from "next/link"
import { SiteNav } from "./site-nav"
import { SiteFooter } from "./site-footer"
import { LESSONS } from "@/lib/lessons"

export function LessonsShell({
  children,
  active,
}: {
  children: React.ReactNode
  active?: string
}) {
  return (
    <main className="min-h-screen">
      <SiteNav />
      <div className="mx-auto grid max-w-6xl gap-10 px-6 py-12 lg:grid-cols-[220px_minmax(0,1fr)]">
        <aside className="lg:sticky lg:top-24 lg:self-start">
          <p className="font-mono text-[10px] uppercase tracking-[0.28em] text-primary">Fleet lessons</p>
          <nav className="mt-4 flex flex-col gap-0.5" aria-label="Lessons">
            <Link
              href="/lessons"
              className={`rounded-lg px-3 py-2 text-sm transition-colors ${
                !active
                  ? "bg-secondary text-foreground"
                  : "text-muted-foreground hover:bg-secondary hover:text-foreground"
              }`}
            >
              Catalog
            </Link>
            {LESSONS.map((l) => (
              <Link
                key={l.slug}
                href={`/lessons/${l.slug}`}
                className={`rounded-lg px-3 py-2 text-sm transition-colors ${
                  active === l.slug
                    ? "bg-secondary text-foreground"
                    : "text-muted-foreground hover:bg-secondary hover:text-foreground"
                }`}
              >
                {l.title}
              </Link>
            ))}
            <Link
              href="/lessons#pack"
              className="rounded-lg px-3 py-2 text-sm text-muted-foreground transition-colors hover:bg-secondary hover:text-foreground"
            >
              Download pack
            </Link>
          </nav>
        </aside>
        <div>{children}</div>
      </div>
      <SiteFooter />
    </main>
  )
}
