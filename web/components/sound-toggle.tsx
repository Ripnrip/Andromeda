"use client"

import { useEffect, useState } from "react"
import { Volume2, VolumeX } from "lucide-react"
import { playUiSound, setUiSoundEnabled, uiSoundEnabled } from "@/lib/ui-sound"

/**
 * Nav toggle for synthesized interface sounds. Opt-in and persistent via
 * localStorage; enabling it plays a confirmation cue so the visitor instantly
 * hears what they turned on. Mirrors ThemeToggle's sizing, styling, and
 * mounted-guard pattern.
 */
export function SoundToggle({ className = "" }: { className?: string }) {
  const [enabled, setEnabled] = useState(false)

  // Sync from localStorage after mount so prerendered HTML stays stable
  // (localStorage does not exist during SSR).
  useEffect(() => setEnabled(uiSoundEnabled()), [])

  /** Flip the persistent preference; the enabling click itself confirms audibly. */
  const toggle = () => {
    const next = !enabled
    setEnabled(next)
    setUiSoundEnabled(next)
    if (next) playUiSound("toggle-on")
  }

  return (
    <button
      type="button"
      onClick={toggle}
      aria-label={enabled ? "Disable interface sounds" : "Enable interface sounds"}
      aria-pressed={enabled}
      title={enabled ? "Disable interface sounds" : "Enable interface sounds"}
      className={`relative inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-lg border border-border bg-card text-muted-foreground transition-colors hover:border-primary/50 hover:text-foreground ${className}`}
    >
      <Volume2
        className={`absolute h-4 w-4 transition-all ${enabled ? "scale-100 rotate-0 opacity-100" : "scale-0 -rotate-90 opacity-0"}`}
      />
      <VolumeX
        className={`absolute h-4 w-4 transition-all ${enabled ? "scale-0 rotate-90 opacity-0" : "scale-100 rotate-0 opacity-100"}`}
      />
      <span className="sr-only">Toggle interface sounds</span>
    </button>
  )
}
