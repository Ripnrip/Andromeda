"use client"

import Link from "next/link"
import type { ComponentProps } from "react"
import { playUiSound } from "@/lib/ui-sound"

/**
 * next/link wrapper that plays the soft "tap" cue on click, letting server
 * components (site nav) emit sound cues without becoming client components
 * themselves. No-op when the visitor has sounds disabled.
 */
export function SoundLink({ onClick, ...props }: ComponentProps<typeof Link>) {
  /** Play the cue first, then honor any caller-supplied click behavior. */
  const handleClick = (e: React.MouseEvent<HTMLAnchorElement>) => {
    playUiSound("tap")
    onClick?.(e)
  }
  return <Link {...props} onClick={handleClick} />
}
