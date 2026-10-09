/**
 * ui-sound.ts — synthesized interface sounds ("audio haptics") for the web UI.
 *
 * Zero-asset WebAudio synth: every cue is generated from oscillators at
 * trigger time, so there are no audio files to fetch, license, or ship.
 * The palette is a C-major pentatonic set with a low-pass filter and short
 * exponential releases, tuned so cues read as "felt" rather than "heard".
 *
 * Opt-in only: nothing plays until the visitor enables sounds with the nav
 * toggle (persisted in localStorage). Every cue site is a user gesture, so
 * the lazily created AudioContext satisfies browser autoplay policy.
 */

export type UiSoundName = "tap" | "pop" | "toggle-on" | "toggle-off" | "success" | "error"

/** localStorage key holding the visitor's sound preference ("on" | "off"). */
const STORAGE_KEY = "andromeda:ui-sound"

/** Master volume for every cue — quiet on purpose; the mix must sit under a conversation. */
const MASTER_GAIN = 0.16

/** Low-pass cutoff applied to the whole mix so no cue turns shrill on bright speakers. */
const FILTER_CUTOFF_HZ = 1800

/** C-major pentatonic frequencies (Hz) the cue palette is built from. */
const NOTE = {
  C4: 261.63,
  E4: 329.63,
  G4: 392.0,
  C5: 523.25,
  D5: 587.33,
  E5: 659.25,
  G5: 783.99,
  A5: 880.0,
  C6: 1046.5,
} as const

/** One synthesized note inside a cue; `at`/`dur` are seconds relative to cue start. */
interface NoteEvent {
  freq: number
  at: number
  dur: number
  level: number
  wave: "sine" | "triangle"
}

/**
 * The cue palette. Keep cues under ~0.6s — audio haptics confirm an action,
 * they must never perform one. Rising lines for "on", falling for "off",
 * arpeggio for success, soft low double-thud for error.
 */
const CUES: Record<UiSoundName, NoteEvent[]> = {
  tap: [{ freq: NOTE.E5, at: 0, dur: 0.1, level: 0.5, wave: "sine" }],
  pop: [
    { freq: NOTE.C5, at: 0, dur: 0.09, level: 0.42, wave: "sine" },
    { freq: NOTE.G5, at: 0.06, dur: 0.13, level: 0.46, wave: "sine" },
  ],
  "toggle-on": [
    { freq: NOTE.C5, at: 0, dur: 0.11, level: 0.42, wave: "sine" },
    { freq: NOTE.E5, at: 0.08, dur: 0.11, level: 0.46, wave: "sine" },
    { freq: NOTE.G5, at: 0.16, dur: 0.16, level: 0.5, wave: "sine" },
  ],
  "toggle-off": [
    { freq: NOTE.G5, at: 0, dur: 0.11, level: 0.42, wave: "sine" },
    { freq: NOTE.E5, at: 0.08, dur: 0.11, level: 0.46, wave: "sine" },
    { freq: NOTE.C5, at: 0.16, dur: 0.16, level: 0.5, wave: "sine" },
  ],
  success: [
    { freq: NOTE.C5, at: 0, dur: 0.16, level: 0.42, wave: "sine" },
    { freq: NOTE.E5, at: 0.09, dur: 0.16, level: 0.46, wave: "sine" },
    { freq: NOTE.G5, at: 0.18, dur: 0.2, level: 0.5, wave: "sine" },
    { freq: NOTE.C6, at: 0.27, dur: 0.3, level: 0.52, wave: "sine" },
  ],
  error: [
    { freq: NOTE.E4, at: 0, dur: 0.16, level: 0.5, wave: "triangle" },
    { freq: NOTE.C4, at: 0.1, dur: 0.22, level: 0.45, wave: "triangle" },
  ],
}

/** Shared AudioContext, created lazily on the first enabled cue (i.e. inside a gesture). */
let ctx: AudioContext | null = null

/**
 * Return the shared AudioContext, creating it on first use and resuming it
 * if the browser suspended it. Returns null on SSR or unsupported browsers;
 * callers treat that as "no sound", never as an error.
 */
function audioContext(): AudioContext | null {
  if (typeof window === "undefined") return null
  if (!ctx) {
    const Ctor = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext
    if (!Ctor) return null
    ctx = new Ctor()
  }
  if (ctx.state === "suspended") void ctx.resume()
  return ctx
}

/**
 * Read the persisted sound preference. Default off — sound on a marketing
 * site without explicit opt-in is hostile, no matter how soothing.
 * Storage failures (Safari private mode) read as "off".
 */
export function uiSoundEnabled(): boolean {
  if (typeof window === "undefined") return false
  try {
    return window.localStorage.getItem(STORAGE_KEY) === "on"
  } catch {
    return false
  }
}

/**
 * Persist the sound preference. Storage failures are swallowed: the toggle
 * still works for the session, it just won't survive a reload in locked-down
 * browsers.
 */
export function setUiSoundEnabled(enabled: boolean): void {
  if (typeof window === "undefined") return
  try {
    window.localStorage.setItem(STORAGE_KEY, enabled ? "on" : "off")
  } catch {
    /* private mode — preference stays session-only */
  }
}

/**
 * Schedule one note: a primary oscillator plus a quiet octave partial for a
 * glass-like tone, through its own exponential envelope, into the shared
 * filtered master bus.
 */
function playNote(context: AudioContext, bus: GainNode, when: number, note: NoteEvent): void {
  const peak = note.level
  for (const [mult, level] of [
    [1, peak],
    [2, peak * 0.28],
  ] as const) {
    const osc = context.createOscillator()
    osc.type = note.wave
    osc.frequency.value = note.freq * mult

    const gain = context.createGain()
    // Fast linear swell in, exponential fade out — percussive but soft.
    gain.gain.setValueAtTime(0, when)
    gain.gain.linearRampToValueAtTime(level, when + 0.008)
    gain.gain.exponentialRampToValueAtTime(0.0001, when + note.dur)

    osc.connect(gain).connect(bus)
    osc.start(when)
    osc.stop(when + note.dur + 0.02)
  }
}

/**
 * Play a UI cue by name. Safe to call anywhere, anytime, as often as liked:
 * it is a no-op when sounds are disabled, before hydration, on hidden tabs
 * (no cue from a background tab), or on browsers without WebAudio.
 */
export function playUiSound(name: UiSoundName): void {
  if (!uiSoundEnabled()) return
  if (typeof document !== "undefined" && document.hidden) return
  const context = audioContext()
  if (!context) return

  // Shared master bus: fixed low-pass into a quiet master gain.
  const filter = context.createBiquadFilter()
  filter.type = "lowpass"
  filter.frequency.value = FILTER_CUTOFF_HZ
  const bus = context.createGain()
  bus.gain.value = MASTER_GAIN
  bus.connect(filter).connect(context.destination)

  const start = context.currentTime + 0.001
  for (const note of CUES[name]) playNote(context, bus, start + note.at, note)
}
