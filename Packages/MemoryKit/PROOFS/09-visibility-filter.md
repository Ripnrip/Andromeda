# Task 9 Proof — VisibilityFilter (cloak / share / export / CloudKit)

**Status:** PASS  
**Date:** 2026-07-15  
**Branch:** `anima-memory`  
**Package:** `Packages/MemoryKit`  
**Spec:** cloak/secrets → `internal`; drop `private`/`internal` from share/export/CloudKit; public vs friends rules

## What was proven

1. **Cloak / secrets → internal** — `[cloak]`, `#cloak`, cloak tags, `[secrets]`/`#secret`, and `secrets`/`secret` tags force `internal` even when suggested visibility is `public`/`friends`.
2. **Credential forcing → internal** — AWS access key, `aws_secret_access_key`, OpenAI `sk-…`, Slack `xox…`, PEM private keys, and `api_key:` / `client_secret=` patterns force `internal`.
3. **Drop private/internal from egress** — `cloudKit` / `externalReplication`, `export` / `friendsExport`, `share` / `publicShare`, and `vectorUpload` all deny `private` and `internal`.
4. **Public / friends rules** — `public` may enter CloudKit, export, vector, and unrestricted share; `friends` may CloudKit/export/vector but **not** unrestricted `share`/`publicShare`.
5. **Local paths stay open** — `ladybugIndex` and `localMaterialization` allow all four classes.
6. **Case-insensitive parse** — `PUBLIC` / `Friends` / ` PRIVATE ` normalize; unknown → `private` (fail closed).
7. **Redaction** — credentials and keyed secrets are replaced with `[🔒 REDACTED …]` banners without rematch loops.
8. **`prepareForEgress`** — classify + redact in one ritual (Task9 proof harness).

## Commands run

```bash
# Hardened sources live in Packages/MemoryKit; verified via isolated solo package
# (avoids parallel-agent SPM lock contention on Packages/MemoryKit/.build)
cd /tmp/visfilter-solo
swift build --build-tests
# Testing.framework symlinked into scratch debug dir for swiftpm-testing-helper
swiftpm-testing-helper --test-bundle-path …/VisibilityFilterSoloPackageTests …
```

Equivalent package filter (when `.build` is uncontended):

```bash
cd /Users/admin/Developer/multibrain/Packages/MemoryKit
swift test --filter VisibilityFilterTests
```

Swift: Apple Swift 6.2 (`swiftlang-6.2.0.19.9`), target `arm64-apple-macosx`.

## Test output summary

| Result | Count |
|--------|------:|
| PASS   | 16 |
| FAIL   | 0 |

Suite: `🛡️ The Visibility Filter and Privacy Gate Rituals` — **passed** (~0.007s runtime after build).

```
Test run with 16 tests in 1 suite passed after 0.007 seconds.
```

Covered cases:

| Test | Proves |
|------|--------|
| Normal Classification | suggested public/friends/private/internal honored when safe |
| Case-Insensitive Visibility | parse + gate normalize mixed case |
| AWS / OpenAI / Slack / PEM / keyed secrets | force `internal` |
| Cloak Tag Forcing | tags + narrative markers → `internal` |
| Secrets Tag Forcing | `secrets`/`secret` tags + markers → `internal` |
| Redaction Rite | credentials scrubbed; no infinite rematch |
| Gateway Verification | private/internal dropped from share/export/CloudKit |
| Public vs Friends Rules | friends blocked from unrestricted share |
| Record Filtering | keypath filter for CloudKit + share + local |
| Leaves Device Map | egress vs on-device targets |
| Task9 Proof Harness | end-to-end cloak/secrets/egress matrix |

## Evidence artifacts

- Log: `/tmp/memorykit-visibility-proof.log`
- Tests: `Tests/MemoryKitTests/VisibilityFilterTests.swift`
- Source: `Sources/MemoryKit/Security/VisibilityFilter.swift`

## Fixes applied during this proof

- **Infinite redaction loop:** keyed-secret replace left `api_key: [🔒 …]` which rematched forever. Fixed by replacing the full match with `[🔒 REDACTED SECRET]` (+ iteration guard).
- **Public vs friends differentiation:** added `publicShare`/`share` (public only) and CloudKit/export aliases.
- **Secrets forcing + case-insensitive parse + `prepareForEgress` / `leavesDevice`.**

## Remaining gaps / stubs

- CloudKitSyncEngine / indexers must call `VisibilityFilter.isAllowed` at their boundaries (Task 3/7/8 wiring — out of this file scope).
- Andromeda mirror: synced for this milestone.

## Andromeda sync

Copied hardened `VisibilityFilter.swift` + `VisibilityFilterTests.swift` + this proof into `~/Developer/Andromeda/Packages/MemoryKit/`.
