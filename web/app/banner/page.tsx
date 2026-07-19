import { ReadmeBanner } from "@/components/readme-banner"

export default async function BannerPage({
  searchParams,
}: {
  searchParams: Promise<{ bare?: string; theme?: string }>
}) {
  const { bare, theme } = await searchParams
  const t = theme === "light" ? "light" : "dark"

  if (bare) {
    return <ReadmeBanner theme={t} />
  }

  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-10 p-8">
      <div className="flex flex-col items-center gap-2">
        <div className="overflow-hidden rounded-xl">
          <ReadmeBanner theme="dark" />
        </div>
        <p className="font-mono text-xs text-muted-foreground">1280 × 400 — dark · /banner?bare=1</p>
      </div>

      <div className="flex flex-col items-center gap-2">
        <div className="overflow-hidden rounded-xl">
          <ReadmeBanner theme="light" />
        </div>
        <p className="font-mono text-xs text-muted-foreground">1280 × 400 — light · /banner?bare=1&theme=light</p>
      </div>
    </main>
  )
}
