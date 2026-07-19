import { DynamicIsland } from "./dynamic-island"
import { MacNotification } from "./mac-notification"

export function SurfacesSection() {
  return (
    <section id="surfaces" className="relative border-t border-border/60 py-20">
      <div className="mx-auto max-w-6xl px-6">
        <div className="mb-3 flex items-center gap-3">
          <span className="h-px w-8 bg-primary/60" />
          <span className="font-mono text-xs uppercase tracking-[0.3em] text-primary">Live surfaces</span>
        </div>
        <h2 className="max-w-3xl text-balance font-serif text-4xl leading-[1.05] tracking-tight md:text-5xl">
          Andromeda speaks through native macOS surfaces
        </h2>
        <p className="mt-4 max-w-2xl text-pretty leading-relaxed text-muted-foreground">
          The control plane never hides its work. A Dynamic-Island live activity perches at the notch while
          capabilities run, and briefs land as first-class macOS notifications — always curtain-safe, never
          leaking a provider brand or a raw secret.
        </p>

        <div className="mt-12 grid gap-6 lg:grid-cols-2">
          {/* Dynamic Island */}
          <div className="flex flex-col rounded-2xl border border-border bg-dotgrid p-8" style={{ backgroundColor: "oklch(0.13 0.018 210)" }}>
            <span className="font-mono text-[11px] uppercase tracking-[0.3em] text-muted-foreground">
              Dynamic-Island live activity
            </span>
            <div className="flex flex-1 items-center justify-center py-10">
              <DynamicIsland />
            </div>
          </div>

          {/* macOS notification */}
          <div
            className="flex flex-col rounded-2xl border border-border p-8"
            style={{
              background:
                "radial-gradient(120% 120% at 80% 0%, oklch(0.3 0.03 200 / 0.35), transparent 60%), oklch(0.16 0.02 210)",
            }}
          >
            <span className="font-mono text-[11px] uppercase tracking-[0.3em] text-muted-foreground">
              macOS notification — brief landed
            </span>
            <div className="flex flex-1 items-center justify-center py-10">
              <MacNotification />
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
