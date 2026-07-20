import { AndromedaMark } from "./andromeda-mark"

export function Wordmark({
  size = "md",
  withMark = true,
}: {
  size?: "sm" | "md" | "lg" | "xl"
  withMark?: boolean
}) {
  const type = {
    sm: "text-2xl",
    md: "text-3xl",
    lg: "text-5xl",
    xl: "text-6xl sm:text-7xl",
  }[size]

  const mark = {
    sm: 24,
    md: 32,
    lg: 48,
    xl: 60,
  }[size]

  return (
    <span className="inline-flex items-center gap-3">
      {withMark && <AndromedaMark size={mark} />}
      <span className={`font-serif leading-none tracking-tight text-foreground ${type}`}>
        Andromeda<span className="text-primary">.</span>
      </span>
    </span>
  )
}
