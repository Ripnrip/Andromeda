import { SiteNav } from "@/components/site-nav"
import { ComingSoonHero } from "@/components/coming-soon-hero"
import { PromiseStrip } from "@/components/promise-strip"
import { ValueTrio } from "@/components/value-trio"
import { MemoryLayers } from "@/components/memory-layers"
import { GraphVector } from "@/components/graph-vector"
import { CurtainSection } from "@/components/curtain-section"
import { HonestStatus } from "@/components/honest-status"
import { Roadmap } from "@/components/roadmap"
import { WaitlistSection } from "@/components/waitlist-section"
import { SiteFooter } from "@/components/site-footer"

export default function HomePage() {
  return (
    <main className="min-h-screen">
      <SiteNav />
      <ComingSoonHero />
      <PromiseStrip />
      <ValueTrio />
      <MemoryLayers />
      <GraphVector />
      <CurtainSection />
      <HonestStatus />
      <Roadmap />
      <WaitlistSection />
      <SiteFooter />
    </main>
  )
}
