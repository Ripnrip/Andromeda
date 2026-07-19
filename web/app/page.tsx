import { SiteNav } from "@/components/site-nav"
import { Hero } from "@/components/hero"
import { PromiseStrip } from "@/components/promise-strip"
import { PillarsSection } from "@/components/pillars-section"
import { CurtainSection } from "@/components/curtain-section"
import { BarDemo } from "@/components/bar-demo"
import { SurfacesSection } from "@/components/surfaces-section"
import { BannerPreview } from "@/components/banner-preview"
import { SiteFooter } from "@/components/site-footer"

export default function HomePage() {
  return (
    <main className="min-h-screen">
      <SiteNav />
      <Hero />
      <PromiseStrip />
      <PillarsSection />
      <CurtainSection />
      <BarDemo />
      <SurfacesSection />
      <BannerPreview />
      <SiteFooter />
    </main>
  )
}
