"use client"

import { useActionState } from "react"
import { useFormStatus } from "react-dom"
import { ArrowRight, Check, Loader2 } from "lucide-react"
import { joinWaitlist, type WaitlistState } from "@/app/actions/waitlist"

const ROLES = ["Engineer", "Founder", "Researcher", "Designer", "Just curious"]

const initialState: WaitlistState = { status: "idle" }

function SubmitButton() {
  const { pending } = useFormStatus()
  return (
    <button
      type="submit"
      disabled={pending}
      className="inline-flex items-center justify-center gap-2 rounded-full bg-primary px-6 py-3 font-medium text-primary-foreground transition hover:opacity-90 disabled:opacity-60"
    >
      {pending ? (
        <>
          <Loader2 className="h-4 w-4 animate-spin" aria-hidden />
          Joining…
        </>
      ) : (
        <>
          Request early access
          <ArrowRight className="h-4 w-4" aria-hidden />
        </>
      )}
    </button>
  )
}

export function WaitlistForm() {
  const [state, formAction] = useActionState(joinWaitlist, initialState)
  const done = state.status === "success" || state.status === "already"

  if (done) {
    return (
      <div className="rounded-2xl border border-primary/30 bg-card p-8 text-center" role="status" aria-live="polite">
        <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-primary/15 text-primary">
          <Check className="h-6 w-6" aria-hidden />
        </div>
        <p className="mt-4 font-serif text-2xl tracking-tight">You&apos;re on the list.</p>
        <p className="mt-2 leading-relaxed text-muted-foreground">
          {state.message} We&apos;re building Andromeda in the open and will reach out as Memory reaches its first
          milestones. No spam — just meaningful progress.
        </p>
      </div>
    )
  }

  return (
    <form action={formAction} className="rounded-2xl border border-border bg-card p-6 md:p-8">
      {/* Honeypot */}
      <div aria-hidden className="absolute left-[-9999px] h-0 w-0 overflow-hidden">
        <label htmlFor="company">Company</label>
        <input id="company" name="company" type="text" tabIndex={-1} autoComplete="off" />
      </div>

      <label htmlFor="email" className="block font-mono text-xs uppercase tracking-[0.2em] text-muted-foreground">
        Email
      </label>
      <input
        id="email"
        name="email"
        type="email"
        required
        autoComplete="email"
        placeholder="you@studio.dev"
        className="mt-2 w-full rounded-xl border border-border bg-background px-4 py-3 text-foreground outline-none ring-primary/40 transition focus:ring-2"
      />

      <fieldset className="mt-5">
        <legend className="font-mono text-xs uppercase tracking-[0.2em] text-muted-foreground">
          I&apos;m a… <span className="normal-case tracking-normal">(optional)</span>
        </legend>
        <div className="mt-3 flex flex-wrap gap-2">
          {ROLES.map((r) => (
            <label
              key={r}
              className="cursor-pointer rounded-full border border-border px-3 py-1.5 text-sm text-muted-foreground transition has-[:checked]:border-primary has-[:checked]:bg-primary/10 has-[:checked]:text-foreground"
            >
              <input type="radio" name="role" value={r} className="sr-only" />
              {r}
            </label>
          ))}
        </div>
      </fieldset>

      <label htmlFor="note" className="mt-5 block font-mono text-xs uppercase tracking-[0.2em] text-muted-foreground">
        What would you want it to remember? <span className="normal-case tracking-normal">(optional)</span>
      </label>
      <textarea
        id="note"
        name="note"
        rows={2}
        maxLength={500}
        placeholder="A note on your workflow, your memory pain, or what you'd build on it."
        className="mt-2 w-full resize-none rounded-xl border border-border bg-background px-4 py-3 text-foreground outline-none ring-primary/40 transition focus:ring-2"
      />

      <div className="mt-6 flex flex-col items-start gap-3 sm:flex-row sm:items-center sm:justify-between">
        <SubmitButton />
        <p className="text-xs leading-relaxed text-muted-foreground">
          {state.status === "error" ? (
            <span className="text-destructive">{state.message}</span>
          ) : (
            "No spam. We email only at real milestones."
          )}
        </p>
      </div>
    </form>
  )
}
