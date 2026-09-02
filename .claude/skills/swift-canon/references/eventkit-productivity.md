# EventKit productivity patterns (Reminders/Calendar from Swift)

Canon for Swift-first personal-productivity plumbing on macOS. Absorbed from the ReminderWatcher pattern (EventKit push → task fan-out) and the remind.swift helper, 2026-08-26.

## Law

Productivity integrations (Reminders, Calendar, Notes-adjacent) are **Swift + native frameworks first** — not osascript, not pip bindings. `EKEventStore` is the door; everything below is zero-dependency.

## The watcher pattern (push, not poll)

```
EKEventStore.requestFullAccessToReminders
  → seed: fetch all, mark seen (never reprocess history)
  → observe .EKEventStoreChanged (push via NotificationCenter)
  → on change: fetch + diff against seen-set (EventKit gives you the event, not the delta)
  → fan out: Process(hermes/multica/…) with a deadline (canon cli-and-process)
  → persist seen-set (cap ~500) to survive restarts
```

Key nuances:
- **Fetch-and-diff, not delta** — `EKEventStoreChanged` doesn't hand you the new items; refetch with `predicateForReminders(in:)` and diff against your seen-set of `calendarItemIdentifier`s.
- **Seed on first run** or every historical reminder fans out once.
- **Cap + persist the seen-set** (`~/.hermes/logs/reminder-watcher-state.json` pattern) — unbounded growth is a slow leak.
- **Permission**: `requestFullAccessToReminders` prompts once per host binary; a compiled helper prompts for *itself*, not your terminal — decide which identity you want prompting.

## One-shot helper pattern (add/list)

- Semaphore-bracket the access request (`wait(timeout: 30)`) — never race the prompt.
- `--in "12h" | --at "yyyy-MM-dd HH:mm"` → `dueDateComponents` **and** `addAlarm(EKAlarm(absoluteDate:))` — a due date without an alarm doesn't notify.
- Priority mapping: EK `1/5/9` = high/medium/low, `0` = none.
- `predicateForReminders` + `fetchReminders` is async-with-callback even in scripts — semaphore-bracket it too.

## Canon fixes when absorbing watcher-style code

1. `task.launchPath` is deprecated — `executableURL` + `arguments` (see `cli-and-process.md`).
2. Every fan-out `Process` needs the **deadline law** (SIGTERM → SIGKILL) — a wedged downstream must not wedge the watcher.
3. Read stdout **and** stderr pipes to EOF after exit; don't share one Pipe for both if you need to distinguish.
4. In Swift 6 strict concurrency this class wants to be an `actor` (or `@MainActor` for the NotificationCenter observer) — the Objective-C callback bridges are the only `@unchecked` seam, hide it in one type.

## Fleet adaptations (our plane)

- Fan-out target is **Multica** (`multica issue create --title … --description-stdin`) or hermes kanban — same watcher, different `Process` line.
- This is exactly the **Loose Ends P2 action lane** (Plans/2026-08-26-loose-ends-product-spec.md): sweep → recap → one-tap "File to Multica". The watcher pattern generalizes: any EventKit/CGWindow/log source → evidence-cited task creation.
- Bundled helper: `~/.pi/agent/skills/apple-reminders/remind.swift` (add/list, zero deps).
