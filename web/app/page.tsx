import { SiteNav } from "@/components/site-nav"
import { ComingSoonHero } from "@/components/coming-soon-hero"
import { PromiseStrip } from "@/components/promise-strip"
import { ValueTrio } from "@/components/value-trio"
import { PillarsSection } from "@/components/pillars-section"
import { MemoryLayers } from "@/components/memory-layers"
import { GraphVector } from "@/components/graph-vector"
import { CurtainSection } from "@/components/curtain-section"
import { HonestStatus } from "@/components/honest-status"
import { FounderStory } from "@/components/founder-story"
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
      <PillarsSection />
      <CurtainSection />
      <HonestStatus />
      <FounderStory />
      <Roadmap />
      <MemoryLayers />
      <GraphVector />
      <WaitlistSection />
      <SiteFooter />
    </main>
  )
}
