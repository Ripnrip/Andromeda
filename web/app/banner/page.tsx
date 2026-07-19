import { ReadmeBanner } from "@/components/readme-banner"

export default function BannerPage() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-8 p-8">
      <div id="export-target" className="overflow-hidden rounded-xl">
        <ReadmeBanner />
      </div>
      <p className="font-mono text-xs text-muted-foreground">
        1280 × 400 — screenshot #export-target for the README PNG
      </p>
    </main>
  )
}
