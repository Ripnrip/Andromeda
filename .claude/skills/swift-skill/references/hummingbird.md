# Hummingbird

Hummingbird 2.x — Swift HTTP server.

## Minimal app

```swift
import Hummingbird

let router = Router()
router.get("/health") { _, _ -> String in "ok" }

let app = Application(
    router: router,
    configuration: .init(address: .hostname("127.0.0.1", port: 8080))
)
try await app.runService()
```

## Middleware

```swift
router.middlewares.add(LogRequestsMiddleware(.info))
router.middlewares.add(ErrorMiddleware())
```

Order: request ID → logging → auth → handler.

## WebSocket

`hummingbird-websocket` package — `router.ws("/ws") { … }`.

## Testing

```swift
try await app.test(.router) { client in
    try await client.execute(uri: "/health", method: .get) { response in
        #expect(response.status == .ok)
    }
}
```

## Security

- Bind `127.0.0.1` for local bridges unless explicitly public
- Validate paths; no directory traversal

## Domain routes

Anima-specific endpoints → **anima-swift** `anima-bridge.md`. Framework patterns → here.
