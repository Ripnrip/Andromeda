# CLI tools & subprocess discipline

Canon distilled from real fleet tools (OpenLoopTracker collector, herd-gather, claude-mem-for-all). All lessons paid for in production.

## Process helpers: deadline or it didn't happen

Every `Process` runner needs a hard deadline. A hung child (hung remote, accidental giant repo, TUI waiting on stdin) must degrade the tool, never stall it.

```swift
private static let timeout: TimeInterval = 5

@discardableResult
static func run(_ command: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = command
    let output = Pipe(); process.standardOutput = output
    process.standardError = Pipe()
    do { try process.run() } catch { return nil }

    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning, Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
    }
    if process.isRunning {
        process.terminate()                      // SIGTERM, polite
        Thread.sleep(forTimeInterval: 0.2)
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        while process.isRunning { Thread.sleep(forTimeInterval: 0.05) }
        return nil                                // timed out → caller degrades
    }
    guard process.terminationStatus == 0 else { return nil }
    return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
}
```

- 50 ms tick polling is cheap and cancellation-safe; no DispatchSemaphore ceremony.
- Read pipes to EOF **after** confirmed exit (avoids the pipe-buffer deadlock of read-before-wait on full pipes).
- Degradation contract: `nil` → caller records "observation unavailable", tool continues.

## Guard against accidental home-rooted git repos

`git -C "$HOME" rev-parse --show-toplevel` *succeeds* when a stray `~/.git` exists and `status --porcelain` then walks the entire home tree (minutes of hang). Guard:

```swift
let standardized = (trimmedRoot as NSString).standardizingPath
let home = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).standardizingPath
if standardized == home || standardized == "/" { return RepositorySnapshot(capturedAt: .now) }
```

## Shipping SwiftPM binaries on macOS (the signing monitor)

- **Always copy fresh** (`rm` + `cp`, new inode) — never overwrite a running binary's path.
- **Re-sign after copy** on beta OSes: `codesign -f -s - <binary> <each @rpath dylib>`. The macOS 26 signing monitor SIGKILLs freshly-copied SwiftPM artifacts with `Code Signature Invalid / Invalid Page` — killing *every* subcommand including `help`, leaving only a ReportCrash trace. Re-signing binary AND dylibs fixes it instantly.
- **rpath law:** a SwiftPM binary linking a dynamic dep (Realm et al.) has rpath `@loader_path` — the dylib must ship *next to the binary*, and the installer must copy it. A binary-only install is dead-on-arrival dyld.
- Installers: build → copy binary + dylibs → re-sign, one block.

## Hash interop with Python (uuid5)

Foundation has no UUID v5. When hashes must match Python's `uuid.uuid5(NAMESPACE_URL, name)`:

```swift
import CryptoKit

func uuid5String(_ name: String) -> String {
    var digest = Insecure.SHA1()
    digest.update(data: Data([0x6b,0xa7,0xb8,0x11,0x9d,0xad,0x11,0xd1,
                              0x80,0xb4,0x00,0xc0,0x4f,0xd4,0x30,0xc8])) // NAMESPACE_URL
    digest.update(data: Data(name.utf8))
    var b = Array(digest.finalize().prefix(16))
    b[6] = (b[6] & 0x0F) | 0x50   // version 5
    b[8] = (b[8] & 0x3F) | 0x80   // RFC 4122 variant
    let hex = b.map { String(format: "%02x", $0) }.joined()
    let i = hex.startIndex
    func s(_ f: Int, _ t: Int) -> String { String(hex[hex.index(i, offsetBy: f)..<hex.index(i, offsetBy: t)]) }
    return "\(s(0,8))-\(s(8,12))-\(s(12,16))-\(s(16,20))-\(s(20,32))"
}
```

Verified byte-identical with Python (cross-language SQLite dedup keyed on the hash).

## Regex gotchas

- `String.range(of:options:[.regularExpression])` uses `NSString.CompareOptions` — **no** dot-matches-newlines flag exists there. For multiline frontmatter/blocks use `NSRegularExpression(pattern:, options: [.dotMatchesLineSeparators])` + `Range(match.range, in:)`.
- Always `.standardizingPath` before comparing filesystem paths.

## Interactive TUI agents from scripts

- Testing a wrapper around a TUI (`pi`, `claude`)? Run `--version` with **stdin from /dev/null** and a hard alarm (`perl -e 'alarm N; exec(...)'`) — otherwise the TUI waits for a terminal forever and looks like a wrapper hang.
- `zsh -i -c 'cmd'` restores sessions and prints banners — bisect wrapper-vs-environment by comparing against a direct-path run.
