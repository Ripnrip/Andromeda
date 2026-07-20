import type { Status } from "@/lib/pillars"
import { STATUS_LABEL } from "@/lib/pillars"

const COLORS: Record<Status, string> = {
  shipped: "var(--shipped)",
  partial: "var(--partial)",
  spec: "var(--spec)",
}

export function StatusDot({
  status,
  withLabel = false,
  pulse = false,
}: {
  status: Status
  withLabel?: boolean
  pulse?: boolean
}) {
  const color = COLORS[status]
  return (
    <span className="inline-flex items-center gap-2">
      <span className="relative flex h-2 w-2">
        {pulse && status === "shipped" && (
          <span
            className="absolute inline-flex h-full w-full animate-ping rounded-full opacity-60"
            style={{ backgroundColor: color }}
          />
        )}
        <span className="relative inline-flex h-2 w-2 rounded-full" style={{ backgroundColor: color }} />
      </span>
      {withLabel && (
        <span className="font-mono text-xs uppercase tracking-wider text-muted-foreground">
          {STATUS_LABEL[status]}
        </span>
      )}
    </span>
  )
}
