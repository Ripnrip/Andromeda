import Image from "next/image"

export function MacNotification() {
  return (
    <div
      className="w-[380px] rounded-[22px] border border-white/10 p-3.5 backdrop-blur-2xl"
      style={{
        background: "oklch(0.28 0.01 220 / 0.72)",
        boxShadow: "0 30px 70px -25px oklch(0.02 0.01 220 / 0.9)",
      }}
    >
      <div className="flex items-start gap-3">
        <Image
          src="/andromeda-icon.png"
          alt="Andromeda"
          width={44}
          height={44}
          className="mt-0.5 shrink-0 rounded-[22%] object-cover"
        />
        <div className="min-w-0 flex-1">
          <div className="flex items-baseline justify-between gap-2">
            <span className="font-mono text-[11px] uppercase tracking-[0.18em] text-foreground/70">Andromeda</span>
            <span className="font-mono text-[11px] text-foreground/50">now</span>
          </div>
          <p className="mt-0.5 font-serif text-lg leading-tight text-foreground">Morning brief is ready</p>
          <p className="mt-1 text-sm leading-snug text-foreground/70">
            6 sessions · 3 projects · 4 open threads. Fleet held GREEN overnight.
          </p>
          <div className="mt-3 flex items-center gap-2">
            <button className="rounded-full bg-primary px-3.5 py-1.5 text-xs font-medium text-primary-foreground transition-opacity hover:opacity-90">
              Open brief
            </button>
            <button className="rounded-full bg-white/10 px-3.5 py-1.5 text-xs font-medium text-foreground transition-colors hover:bg-white/15">
              Recall
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}
