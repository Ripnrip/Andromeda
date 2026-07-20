"use server"

import { db } from "@/lib/db"
import { waitlist } from "@/lib/db/schema"
import { eq } from "drizzle-orm"

export type WaitlistState = {
  status: "idle" | "success" | "already" | "error"
  message?: string
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

export async function joinWaitlist(_prev: WaitlistState, formData: FormData): Promise<WaitlistState> {
  // Honeypot: bots fill hidden fields
  if ((formData.get("company") as string)?.trim()) {
    return { status: "success", message: "You're on the list." }
  }

  const email = String(formData.get("email") ?? "").trim().toLowerCase()
  const role = String(formData.get("role") ?? "").trim() || null
  const note = String(formData.get("note") ?? "").trim().slice(0, 500) || null

  if (!EMAIL_RE.test(email)) {
    return { status: "error", message: "Enter a valid email address." }
  }

  try {
    const existing = await db
      .select({ id: waitlist.id })
      .from(waitlist)
      .where(eq(waitlist.email, email))
      .limit(1)

    if (existing.length > 0) {
      return { status: "already", message: "You're already on the list — we'll be in touch." }
    }

    await db.insert(waitlist).values({ email, role, note })
    return { status: "success", message: "You're on the list. Welcome aboard." }
  } catch (err) {
    console.log("[v0] waitlist insert error:", err instanceof Error ? err.message : err)
    return { status: "error", message: "Something went wrong. Please try again." }
  }
}
