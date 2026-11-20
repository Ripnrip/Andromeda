# Anti-Patterns — DO NOT WRITE LIKE THIS

Real exhibits from real reviews — code that shipped or nearly shipped. Each
shows the offending code as authored, why it fails Swift 6 / modern craft
review, and the approved replacement shape. When a review comment or skill
rule points here, the exhibits are normative.

---

## Exhibit 1 — Hand-rolled dynamic JSON where the protocol is closed

### ❌ DO NOT WRITE LIKE THIS

```swift
enum JSONValue: Decodable, @unchecked Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let b = try? container.decode(Bool.self) { self = .bool(b) }
        else if let n = try? container.decode(Double.self) { self = .number(n) }
        else if let s = try? container.decode(String.self) { self = .string(s) }
        else if let a = try? container.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? container.decode([String: JSONValue].self) { self = .object(o) }
        else { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unsupported JSON")) }
    }

    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    // … intValue, arrayValue, objectValue, plus a hand-rolled `encoded`
    // that re-escapes strings through JSONSerialization and formats
    // numbers by hand.
}
```

The escaping helper is the tell:

```swift
private static func escaped(_ raw: String) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: [raw]) else { return raw }
    let text = String(decoding: data, as: UTF8.self)
    return String(text.dropFirst().dropLast())
}
```

…followed by dictionary-poking at every call site:

```swift
let name = request.params?.objectValue?["name"]?.stringValue ?? ""
let path = args["path"]?.stringValue
```

### Why this fails review

1. **`@unchecked Sendable` as a band-aid.** An enum of `Sendable` payloads is
   implicitly `Sendable` — the compiler proves it for free. Writing
   `@unchecked` discards that proof and asserts one nobody verified, and the
   annotation clones itself by copy-paste. `@unchecked` is for wrapping
   legacy reference state behind a stated invariant, never for value types.
2. **`try?` chains destroy error evidence.** Every decode failure collapses
   to `nil`; a malformed message is indistinguishable from a missing field.
   `DecodingError` carries the coding path — the exact thing a caller needs —
   and this style throws it away at the door.
3. **Hand-rolled escaping/formatting.** The `escaped` helper round-trips
   JSONSerialization on a one-element array just to borrow its escaping,
   then string-slices the brackets off. Worse, on encoder failure it
   `return raw` — **unescaped text emitted into a JSON document**, i.e.
   silent corruption. `JSONEncoder` owns escaping, number formatting, and
   (with `.sortedKeys`) deterministic ordering.
4. **The schema already exists — encode it.** A server that defines every
   method, tool, and argument is a closed protocol; per-method `Codable`
   structs make illegal messages unrepresentable instead of
   representable-but-wrong. A dynamic JSON type is a seam of last resort
   for genuinely open-world payloads, not a default.
5. **Stringly-typed access spreads.** `objectValue?["name"]?.stringValue ?? ""`
   at each call site is an untyped contract. Typos type-check. Renames miss
   sites. The compiler is locked out of the protocol.
6. **One god-file.** JSON model + escaping + process spawning + engine
   lookup + tool dispatch + server loop in a single file. None of it can be
   unit-tested without spawning a process.

### ✅ Write like this instead

Typed request/response models; the dynamic enum disappears. When dispatch
must happen before the payload type is known (JSON-RPC method routing),
decode in two typed passes over the same bytes:

```swift
enum RPCID: Hashable, Sendable, Codable {
    case number(Int)
    case string(String)
    // custom Codable for the number-or-string id shape
}

// Pass 1 — route on the method.
struct RPCRequestHeader: Decodable {
    let id: RPCID?
    let method: String
}

// Pass 2 — decode the same bytes with full type information.
struct ToolCallRequest<Arguments: Decodable>: Decodable {
    struct Params: Decodable {
        let name: String
        let arguments: Arguments?
    }
    let id: RPCID?
    let params: Params
}

struct CodeSearchArguments: Decodable {
    let pattern: String          // required — absent = DecodingError with path
    let path: String?
    let language: String?
}
```

Responses are concrete `Encodable` payloads in generic envelopes. Escaping,
formatting, and key order belong to `JSONEncoder` (`.sortedKeys` for
deterministic output). Decode failures surface as typed errors carrying the
coding path — reply `-32602 Invalid params` with the real reason, never a
silent `nil`.

Rules this exhibit generalizes to:

- A dynamic JSON type is a **protocol seam last resort**, not a default. If
  the message set is closed, it gets `Codable` models.
- `try?` at a trust boundary converts "malformed" into "absent." Decode
  boundaries `do/catch` and propagate evidence.
- If a `try?` probe order is load-bearing (e.g. `Bool` before `Double` or
  `true` decodes as `1.0`), the order is a contract: document it and pin it
  with a test.
- `@unchecked Sendable` requires a comment naming the invariant that makes
  it true (reference-semantics OS handles confined to one spawn function
  qualify; "I didn't want to fix the error" does not).
- Layer pure core (models, decode, presentation) away from the effect shell
  (processes, stdio) so both are testable alone.

---

## Exhibit 2 — Ad-hoc child-process plumbing around `Process`

### ❌ DO NOT WRITE LIKE THIS

```swift
let completion = DispatchSemaphore(value: 0)
DispatchQueue.global().async {
    process.waitUntilExit()      // Process captured in a @Sendable closure
    completion.signal()
}
completion.wait()
// pipes drained by manually nil-ing readabilityHandlers afterwards
```

Semaphores + global queues + manual handler teardown is 2019 shape, and
capturing `Process` in `@Sendable` closures is a Swift 6 error (or worse, an
`@unchecked` silence).

### ✅ Write like this instead

Confine each spawn to one async function; only `Sendable` values cross.
`terminationHandler` + `withCheckedContinuation` for exit, `async let` for
concurrent pipe drainage, task-group race for timeouts:

```swift
func run(_ command: Command) async throws -> Output {
    // Process lives and dies inside this function.
    async let stdout = Self.drain(outPipe.fileHandleForReading)
    async let stderr = Self.drain(errPipe.fileHandleForReading)
    let status = await withCheckedContinuation { continuation in
        process.terminationHandler = { terminated in
            continuation.resume(returning: terminated.terminationStatus)
        }
    }
}
```

---

## Exhibit 3 — Awaiting exit before draining child pipes

### ❌ DO NOT WRITE LIKE THIS

```swift
try process.run()
process.waitUntilExit()              // blocks while the child…
let data = pipe.fileHandleForReading // …blocks writing into a full pipe
    .readDataToEndOfFile()
```

Classic mutual deadlock: the child blocks once the OS pipe buffer (~64 KB)
fills; the parent blocks waiting for exit; nobody proceeds. It passes every
toy fixture and dies on the first 10,000-match payload — a code-review
reproduction, not a hypothetical.

### ✅ Write like this instead

Start both drains **before** awaiting exit (see Exhibit 2's `async let`
shape), or stream chunks via `readabilityHandler` → `AsyncStream`. The
drain must be concurrent with execution, not sequenced after it.

---

## Exhibit 4 — Per-byte `AsyncBytes` iteration for bulk pipe reads

### ❌ DO NOT WRITE LIKE THIS

```swift
for try await byte in handle.bytes {
    data.append(byte)   // 1.4 MB ≈ 1.4M suspension points
}
```

Each byte is an async hop. Measured in review: a 3,000-match (~1.4 MB)
search response blew a 120 s timeout; the same payload drains in under a
second with chunked or blocking reads. Big-O hides a scheduler constant
here, and the constant wins.

### ✅ Write like this instead

Chunked streams (`readabilityHandler` → `AsyncStream(Data)`) for streaming,
or park a dispatch thread — never a cooperative-pool thread — on the
blocking read:

```swift
private static func drain(_ handle: FileHandle) async -> Data {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
            continuation.resume(returning: handle.readDataToEndOfFile())
        }
    }
}
```

`.lines` is fine for line-framed, small payloads. `.bytes` per-byte is for
parsing, not bulk transfer.

---

## Exhibit 5 — Hand-rolled `encode(to:)` for an entire struct to keep one key null

One optional key with special wire semantics (`id` must encode as `null`,
never be omitted — JSON-RPC 2.0 requires it present on error responses) does
not justify taking over the whole type's encoding.

### ❌ DO NOT WRITE LIKE THIS

```swift
struct RPCErrorResponse: Encodable, Sendable {
    let jsonrpc = "2.0"
    let id: RPCID?
    let error: Error

    enum CodingKeys: String, CodingKey { case jsonrpc, id, error }

    /// JSON-RPC 2.0: the `id` member is REQUIRED on responses and MUST be
    /// null — not absent — when the request id could not be determined
    /// (parse errors, invalid requests). Synthesized conformance would
    /// `encodeIfPresent` and silently drop the key.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        if let id {
            try container.encode(id, forKey: .id)
        } else {
            try container.encodeNil(forKey: .id)
        }
        try container.encode(error, forKey: .error)
    }
}
```

The custom `encode(to:)` fixes the one key and assumes custody of all the
rest. Every future field becomes a manual `encode(_:forKey:)` line; miss one
and it silently vanishes from the wire — a regression no compiler diagnostic
catches. The intent ("this key is present, `null` when nil") lives in the
type's plumbing instead of at the property where it belongs.

### ✅ Write like this instead

A property wrapper that states the wire rule once, reusable by any key on
any type; the struct keeps fully synthesized encoding:

```swift
@propertyWrapper
struct EncodeNull<Value: Encodable & Sendable>: Encodable, Sendable {
    var wrappedValue: Value?

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        if let wrappedValue {
            try container.encode(wrappedValue)
        } else {
            try container.encodeNil()
        }
    }
}

struct RPCErrorResponse: Encodable, Sendable {
    let jsonrpc = "2.0"

    @EncodeNull var id: RPCID?

    let error: Error
}
```

The rule is visible at the declaration site, the mechanism is tested once in
the wrapper, and new fields encode themselves. Same technique generalizes to
other key-presence semantics (always-empty-array, explicit booleans).

---

## Exhibit 6: enum labels built by `rawValue` concatenation

**Shape**: deriving a label or ID inside an enum with runtime string math.

Real offender (AndromedaUI `PillarStates.swift`, flagged by BofA 2026-08-17):

```swift
public enum MemoryState: String, PillarState {
    case forming, consolidating, recalled, decaying, conflicted

    public var label: String { "memory." + rawValue }   // ← drifts silently
}
```

**Why it's wrong** (numbered failures):

1. **Silent drift.** Rename `.consolidating` to `.linking` and the label
   changes from `memory.consolidating` to `memory.linking` with zero compiler
   signal — if that label is a client-facing capability ID, the contract broke
   invisibly.
2. **Hidden conditional variants compound it.** The sibling site read
   `"memory." + (self == .procedural ? "steps" : rawValue)` — string math
   encoding case-specific business rules that belong in the switch.
3. **Half-migrated call sites.** The same codebase hand-types the literals the
   enums own: `hasPrefix("memory_retain")` next to
   `case memoryRetain = "memory_retain"` (~20 sites, 9 files for the
   `infer.write`/`memory.*` family).

**Replacement shape**:

```swift
public var label: String {
    switch self {
    case .forming:       "memory.forming"
    case .consolidating: "memory.consolidating"
    case .recalled:      "memory.recalled"
    case .decaying:      "memory.decaying"
    case .conflicted:    "memory.conflicted"
    }
}
```

Exhaustive, compiler-checked, and renaming a case forces a label decision at
the switch. Call sites use `MemoryState.recalled.rawValue` — the enum
declaration is the single source of truth for the contract string.

CI enforcement: `canon/ast-grep/enum-raw-value-concat.yml` and
`canon/ast-grep/bare-capability-literal.yml` (warning severity until the
existing sites are cleaned via HAB-316/317, then error).

## Exhibit 7 — A `.task`-gated "settled" state (reduce-motion stills that render void)

**The scar (Andromeda PR #61, Aug 2026 — merged, then fixed in-PR):** the
orchestrator console's `EntranceModifier` gated its settled state on a task:

```swift
@State private var shown = false
content
    .opacity(shown ? 1 : 0)
    .task {
        guard !reduceMotion else { shown = true; return }   // ← never runs offscreen
        try? await Task.sleep(for: .seconds(stagger))
        withAnimation(OrchestratorMotion.entrance) { shown = true }
    }
```

Under reduce motion the "still frame" is supposed to be the settled frame.
But snapshot hosts and offscreen pre-heat do not reliably start `.task`s for
ScrollView-hosted content — so the recorded "still" was `opacity(0)`: a
2-unique-color void. All 47 baselines were green against nothing
(vacuously green suite), and the wall shipped in the PR body as a dark
rectangle.

**The replacement shape — settled state derives from the environment:**

```swift
let settled = shown || reduceMotion
content
    .opacity(settled ? 1 : 0)
    .offset(y: settled ? 0 : 12)
    .task { /* animate to shown when motion is allowed */ }
```

The same law covers any environment-derivable determinism (clocks, RNG,
locale): inject and derive, never hope a task fires. CI enforcement for the
baseline side: `BaselineIntegrityTests` (a committed baseline that is a
2-color flat image fails the suite).

## Exhibit 8 — Lazy containers for fixed, small collections

`LazyVStack`/`LazyVGrid` defer materialization until "needed" — and offscreen
hosts (snapshot capture, Xcode canvas pre-heat) never need them, rendering
empty voids where content should be. Laziness is an optimization for large
or unbounded collections; a fixed 28-specimen wall gains nothing and pays in
nondeterminism. Eager `VStack` + chunked rows render identically everywhere.

Rule of thumb: **lazy only when the count is unbounded or the cells are
expensive; fixed collections are eager.**

## Exhibit 9 — `@_nonSendable(_assumed)` types crossing isolation as returns

AppKit SDKs mark `NSImage` `@_nonSendable(_assumed)` — its Sendable
conformance is explicitly unavailable, and `@preconcurrency import` CANNOT
suppress that (different mechanism from ordinary non-Sendable). Returning it
from `MainActor.assumeIsolated { … }` compiles on Xcode 26 and fails on the
macos-15 CI toolchain — "compiles locally" proves nothing.

**The replacement shape — return Void, hand the value through an
`@unchecked Sendable` box (same thread end-to-end):**

```swift
private final class ImageBox: @unchecked Sendable { var image: NSImage? }
// inside the pullback:
let box = ImageBox()
MainActor.assumeIsolated { box.image = makeImage(view) }   // returns Void
return box.image!
```

## Exhibit 10 — A tolerant record lane re-shipping committed files as "fresh" output

A CI record step with `continue-on-error: true` (needed because record mode
fails tests on purpose) also swallows COMPILE failures. When compilation
dies, the artifact upload globs pick up the previously committed baselines
and upload them unchanged — indistinguishable from fresh output. Landed
once as "runner-recorded baselines" that were byte-identical studio bytes.

**The gates:** (1) strict `swift build --build-tests` step before the
tolerant record step; (2) never claim artifact provenance without a
byte-diff (`shasum` artifact vs committed — identical bytes = the run
produced nothing).

## How to use this file in review

When a diff matches an exhibit's shape, cite the exhibit, name which
numbered failure applies, and require the replacement shape. New exhibits
get added here with the real offending code — verbatim, with provenance —
after the fix lands, so the canon accumulates scars instead of forgetting
them.

## Provenance

Exhibits 1–2: a Swift-native MCP stdio server's first draft and its PR
review cycle (Aug 2026). Exhibit 3: the same review's deadlock reproduction
at 10,000 matches. Exhibit 4: the over-correction that followed — an async
rewrite that was itself caught by a 3,000-match regression test. Exhibit 5:
the same server's error-response encoder (PR #48) — hand-rolled keyed
encoding replaced by an `@EncodeNull` property wrapper proposed in review.
Exhibit 6: AndromedaUI enum labels via `rawValue` concatenation — flagged by
BofA in review (Aug 2026), swept repo-wide in issue #57, enforcement rules
in `canon/ast-grep/`. Exhibits 7–10: the Andromeda orchestrator
console landing (PR #61, Aug 2026) — the void-gallery incident chain: a
green-against-void snapshot suite, offscreen lazy materialization, an
NSImage Sendable toolchain split that hid inside a tolerant record lane, and
the artifact-provenance byte-diff rule born from landing stale bytes as
"runner-recorded".
Project-specific scar details live in the project skill layered on this canon.

## Exhibit 7: snapshot tests that capture animated or reveal states without pinning the random source

**Shape**: a snapshot suite records a view whose pixels depend on anything
time-, RNG-, or appearance-dependent — then passes locally and flakes on
re-run or on the CI runner.

Real offender (AndromedaOrchestrator landing, 2026-08-26): a catalogue
sweep spec passed its own record run, then failed the very next verify run.
The moving part was not animation — it was a demo model that re-rolled its
`requests` array with `Double.random` on every process launch, so the
recorded baseline and the verify render were different data wearing a
deterministic-looking costume.

**Why it's wrong** (numbered failures):

1. **The flake hides behind an obvious suspect.** "Animation
   nondeterminism" was the tempting diagnosis; the actual cause was an
   unpinned data array. Chasing the visible animation while the data
   re-randomizes wastes a debugging cycle in exactly the confident
   direction.
2. **Cross-process RNG beats per-run freezes.** Freezing the ticker
   (`isStreaming = false`) is not enough when the *initial* fixtures are
   random — record and verify are separate processes with separate dice.
3. **`.task`-driven reveals capture invisible frames.** A modifier that
   starts `shown = false` and reveals from its `.task` is captured pre-task
   by a synchronous draw: every baseline renders as an empty panel —
   consistently, which looks stable until you notice the panels are blank.
4. **SDK-stable assumptions rot.** `accessibilityReduceMotion` was writable
   for a decade of SwiftUI; the macOS 26 SDK made it get-only. Code that
   compiled "forever" fails with an overload-resolution error that looks
   like a type-inference flake (and was documented as one, wrongly, in a
   prior memory file).

**Replacement shape**:

```swift
// Pin the data in the SOURCE module — gallery and tests share one truth:
public extension SampleData {
    static let deterministicRequests: [GatewayRequest] = [ /* fixed rows */ ]
}

// Host: still frame via the SPI key (macOS 26+) + runloop pump for .task reveals:
let themed = view
    .environment(\._accessibilityReduceMotion, true)   // get-only public key on macOS 26 SDK
    .environment(\.colorScheme, dark ? .dark : .light)
    .frame(width: size.width, height: size.height)
let vc = NSHostingController(rootView: AnyView(themed))
let window = NSWindow(contentViewController: vc)
window.displayIfNeeded(); window.display()
RunLoop.main.run(until: Date().addingTimeInterval(0.4))   // let .task closures land
window.contentViewController = nil
// then assertSnapshot(of: vc, ...) — state persists on the hosting controller
```

Canon rule: a snapshot suite must force **every** nondeterminism source —
data RNG, ambient loops, entrance timing, appearance — to a still, complete
frame with pinned content before capture. Verify by running the suite twice
back-to-back and diffing, before ever pushing a `[record-snapshots]` tip.
Proven in `Ripnrip/Andromeda` PR #61 (34/34 ×2 byte-stable).
## Exhibit 11 — The Go-shaped actor: porting another language's structure instead of its meaning

**Shape**: a rewrite that carries the old language's imperative flow into Swift — policy
inline in the actor, concrete dependencies with no seam, strings where enums belong.

Real offender (multica `server-swift` Phase 0 first draft, flagged in review 2026-08-26,
fixed same session in HAB-374):

```swift
public actor PoolOfSouls {
    // ❌ decision logic inline in the actor — untestable without a database
    if let rested = idle.popLast() { soul = rested }          // branch 1
    else if total < config.maxConns { soul = try await summonSoul() }  // branch 2
    else { emptyAcquireCount += 1                              // branch 3 — the wait case
           soul = try await withCheckedThrowingContinuation { ... } }
}
```

**Why it's wrong** (numbered failures):

1. **Policy trapped in the shell.** Admission (idle-reuse vs summon vs wait) is a pure
   function of `(idle, total, max)` — inline in an actor over a live PostgresNIO
   connection, it can only be tested against a real database.
2. **Concrete dependency, no seam.** Naming `PostgresConnection` directly means no
   scripted souls, no fake summoner, zero unit tests of custody logic.
3. **Stringly-typed moods.** `pressure: "gathering"` as a String field — typos compile;
   galleries can't switch exhaustively.
4. **Field-list parity, not meaning parity.** Porting pgxpool's `Stat()` fields verbatim
   without asking which *decisions* the numbers feed.

**Replacement shape** (what shipped): pure `Admission.decide(idle:total:max:)` +
`Pressure` enum (sigil/caption via exhaustive switch — Exhibit 6 discipline) +
`ConnectionSummoner`/`PooledConnection` protocols so tests stage scripted souls; the
actor keeps custody only. Testing went from "needs a database" to 9/9 pure-table tests
in 0.001s.

**Provenance**: multica Go→Hummingbird rewrite (HAB-374), 2026-08-26. Originally
appended to the `~/.agents` sync copy as Exhibit 8 — **clobbered by the PR #63 canon
sync**, restored here as Exhibit 11. Meta-lesson now law: canon edits land in the
git-tracked source (this file), never the synced copy.
