# Logging

Default to `os.Logger` and structured log intent.

## Baseline

```swift
import OSLog

let logger = Logger(subsystem: "com.example.app", category: "sync")
logger.info("Starting sync for \(itemCount, privacy: .public) items")
```

## Rules

- Log structured events, not diary entries.
- Include useful dimensions: IDs, counts, phase, status.
- Never log secrets, tokens, raw auth headers, or user-private payloads unless explicitly scrubbed.
- Use log levels honestly: `debug`, `info`, `notice`, `warning`, `error`, `fault`.

## Emoji conventions

Emoji prefixes are optional. Use them only if they improve scanability and remain consistent.

Good:

```swift
logger.notice("✅ Cache warmed")
logger.warning("⚠️ Retry scheduled")
logger.error("❌ Upload failed: \(error.localizedDescription, privacy: .public)")
```

Bad:

- random emoji soup
- emoji replacing real severity or metadata
- emoji on every line until the log becomes theater

## Review questions

- Would this log help diagnose the failure quickly?
- Is the privacy level appropriate?
- Is the emoji convention consistent or just noise?
- Should this be a metric/span instead of a log line?


## Emoji-prefixed, typed internal events (Aug 2026)

Internal observability is a product surface, not an afterthought — BofA
directive: "no observability/emoji-logging internally" is a review blocker.

- **One event enum, associated values, never call-site strings:**
  `case screenChanged(Screen)` — glyph/name/summary derived in single
  switches. `Codable` for export, `Sendable` for crossing.
- **One bridge to `os.Logger`** — emoji rides on the event, categories map
  to log streams; no format strings scattered around the codebase.
- **An observable ring journal** (`capacity` is a named constant) feeds an
  in-app surface (the States screen's SELF section in the orchestrator
  console) — observability exists before providers wire up.
- Clocks in journal views read an injected environment value so snapshots
  stay deterministic.
