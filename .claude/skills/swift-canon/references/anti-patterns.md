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
Project-specific scar details live in the project skill layered on this canon.
