# Anti-Patterns — DO NOT WRITE LIKE THIS

Real exhibits from this repo's PRs. Each shows the offending code as authored,
why it fails Swift 6 / modern craft review, and the approved replacement shape.
When a review comment or skill rule points here, the exhibits are normative.

---

## Exhibit 1 — Hand-rolled dynamic JSON enum (AndromedaMCP, PR #46)

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
    var boolValue: Bool? { if case .bool(let b) = self { return b }; return b }
    // … intValue, arrayValue, objectValue, plus a hand-rolled `encoded`
    // that re-escapes strings through JSONSerialization and formats
    // numbers by hand.
}
```

Followed by dictionary-poking at every call site:

```swift
let name = request.params?.objectValue?["name"]?.stringValue ?? ""
let path = args["path"]?.stringValue
```

### Why this fails review

1. **`@unchecked Sendable` as a band-aid.** The type is only `Sendable` because
   someone wrote the words. Swift 6 sendability errors are design feedback:
   make the value genuinely `Sendable` (it is — this is papering), or restructure
   so nothing unsound crosses. Slapping `@unchecked` on an enum of values to
   silence the compiler teaches reviewers nothing and hides real risk elsewhere.
2. **`try?` chains destroy error evidence.** Every decode failure collapses to
   `nil`. A malformed `tools/call` is indistinguishable from a missing field.
   Codable's `DecodingError` carries the coding path — the exact thing a caller
   needs — and this style throws it away at the door.
3. **Hand-rolled JSON escaping/formatting.** `JSONEncoder` owns escaping,
   number formatting, and sorting. Re-implementing it via a `JSONSerialization`
   round-trip is untestable surface area that will drift from real JSON.
4. **The schema already exists — encode it.** The server defines every method,
   every tool, and every argument. This is a closed protocol; per-method
   `Codable` structs make illegal messages unrepresentable instead of
   representable-but-wrong.
5. **Stringly-typed access spreads.** `objectValue?["name"]?.stringValue ?? ""`
   at each call site is an untyped contract. Typos type-check. Renames miss
   sites. The compiler is locked out of the protocol.
6. **One god-file.** JSON model + escaping + process spawning + engine lookup +
   tool dispatch + server loop in a single file. None of it can be unit-tested
   without spawning a process.

### ✅ Write like this instead

Typed request/response models; the dynamic enum disappears. When dispatch must
happen before the payload type is known (JSON-RPC method routing), decode in
two typed passes over the same bytes:

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

Responses are concrete `Encodable` payloads in generic envelopes:

```swift
struct RPCResult<Response: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id: RPCID?
    let result: Response
}
```

Escaping, formatting, and key order belong to `JSONEncoder` (`.sortedKeys` for
deterministic output). Decode failures surface as typed errors carrying the
coding path — reply `-32602 Invalid params` with the real reason, never a
silent `nil`.

Rules this exhibit generalizes to:

- A dynamic JSON type is a **protocol seam last resort**, not a default. If the
  message set is closed, it gets `Codable` models.
- `try?` at a trust boundary converts "malformed" into "absent." Decode
  boundaries `do/catch` and propagate evidence.
- `@unchecked Sendable` requires a comment naming the invariant that makes it
  true (reference-semantics OS handles confined to one spawn function qualify;
  "I didn't want to fix the error" does not).
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

`Process` is not `Sendable`; capturing it in `@Sendable` closures is a Swift 6
error (or worse, an `@unchecked` silence). Semaphores + global queues + manual
handler teardown is 2019 shape.

### ✅ Write like this instead

Confine each spawn to one async function; only `Sendable` values cross.
`terminationHandler` + `withCheckedContinuation`, `AsyncStream` for pipe
drainage, task-group race for timeouts. If a reference handle must cross into a
`@Sendable` closure, wrap it in a named `@unchecked Sendable` box whose comment
states the thread-safety invariant — one box, documented, reviewable:

```swift
func run(_ command: Command) async throws -> Output {
    // Process lives and dies inside this function.
    let status = await withCheckedContinuation { continuation in
        process.terminationHandler = { terminated in
            continuation.resume(returning: terminated.terminationStatus)
        }
    }
}
```

---

## How to use this file in review

When a diff matches an exhibit's shape, cite the exhibit, name which numbered
failure applies, and require the replacement shape. New exhibits get added here
with the real offending code — verbatim, with PR reference — after the fix
lands, so the canon accumulates scars instead of forgetting them.
