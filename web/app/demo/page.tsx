import Link from "next/link"
import { ArrowLeft } from "lucide-react"
import { Hero } from "@/components/hero"
import { PromiseStrip } from "@/components/promise-strip"
import { PillarsSection } from "@/components/pillars-section"
import { CurtainSection } from "@/components/curtain-section"
import { BarDemo } from "@/components/bar-demo"
import { SurfacesSection } from "@/components/surfaces-section"
import { Manifesto } from "@/components/manifesto"
import { Wordmark } from "@/components/wordmark"

export const metadata = {
  title: "Andromeda — Internal Demo",
  robots: { index: false, follow: false },
}

export default function DemoPage() {
  return (
    <main className="min-h-screen">
      <header className="sticky top-0 z-50 border-b border-border/60 bg-background/70 backdrop-blur-xl">
        <nav className="mx-auto flex h-16 max-w-6xl items-center justify-between px-6">
          <Link href="/" className="flex items-center">
            <Wordmark size="sm" />
          </Link>
          <div className="flex items-center gap-2">
            <span className="hidden font-mono text-xs uppercase tracking-wider text-muted-foreground sm:inline">
              Internal demo
            </span>
            <Link
              href="/"
              className="inline-flex items-center gap-2 rounded-lg border border-border bg-card px-4 py-2 text-sm font-medium text-foreground transition-colors hover:border-primary/50 hover:text-primary"
            >
              <ArrowLeft className="h-4 w-4" />
              Back to site
            </Link>
          </div>
        </nav>
      </header>
      <Hero />
      <PromiseStrip />
      <PillarsSection />
      <CurtainSection />
      <BarDemo />
      <SurfacesSection />
      <Manifesto />
    </main>
  )
}
