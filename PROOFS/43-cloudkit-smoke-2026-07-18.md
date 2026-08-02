# PROOF 43 — CloudKit sync smoke (BIN-79): agent-verified vs human-only

**Date:** 2026-07-18 (~15:40 EDT)
**Lane:** MemoryKit `CloudKitSyncEngine` / Andromeda sync surface
**Ticket:** BIN-79 (Linear, Binary-bros) — CloudKit GUI smoke · Multica mirror HAB-86
**SoT:** Andromeda `PROOFS/` (this file) · mirror `~/Developer/multibrain/PROOFS/43-cloudkit-smoke-2026-07-18.md`
**Related:** [PROOF 40 memorykit-live](../../multibrain/PROOFS/40-memorykit-live-studio-2026-07-18.md) · [PROOF 42 test catalog](./42-test-and-snapshot-catalog-2026-07-18.md)
**Honesty rule:** report only what was actually observed. This proof does **not** claim any real iCloud/CloudKit round-trip or cross-device sync — none was performed, and none is currently possible from this tree (see §3).

---

## TL;DR

The "GUI smoke" for BIN-79 is **genuinely human/GUI + provisioning work** and cannot be completed headlessly from the current tree. The **engine logic** is fully agent-verified against a protocol mock (12/12 CloudKit unit tests pass), but there is **no signed `.app`, no iCloud/CloudKit entitlement, and no CloudKit container** wired anywhere in either repo — so no real push to Apple's private DB has (or can) occur without a human at a GUI. BIN-79 stays **Todo/In-Progress** with a tight human checklist below.

---

## 1. What the "GUI smoke" actually requires

`CloudKitSyncEngine` performs a **one-way local → CloudKit private-DB push** through a `CloudKitDatabase` protocol seam:

```82:95:Packages/MemoryKit/Sources/MemoryKit/Sync/CloudKitSyncEngine.swift
public protocol CloudKitDatabase: Sendable {
    func save(_ record: CKRecord) async throws -> CKRecord
    ...
}
extension CKDatabase: CloudKitDatabase {}
```

The seam means **all engine behaviour is unit-testable in isolation** (a mock conforms to `CloudKitDatabase`). But a real smoke — actually landing a record in Apple's private CloudKit vault and watching it appear on another device — requires the full Apple stack:

- A **signed app bundle** with the `com.apple.developer.icloud-services` + `com.apple.developer.icloud-container-identifiers` entitlements.
- A provisioning profile bound to an **Apple Developer team** and a provisioned **CloudKit container** (`iCloud.<bundle-id>`).
- A device **signed into a real iCloud account** via macOS **System Settings → Apple Account → iCloud** (with the app's iCloud toggle on).
- Construction of `CKContainer(identifier:).privateCloudDatabase` and injection into `CloudKitSyncEngine(ckDatabase:)`.

None of the above is a `swift test` / CLI operation. There is **no headless verification path** to a real container: CloudKit auth, entitlement enforcement, and the iCloud account daemon are all OS/GUI-gated.

## 2. Agent-verified: CloudKit unit tests (real counts)

Ran the CloudKit-specific suite in the multibrain SoT:

```
cd ~/Developer/multibrain/Packages/MemoryKit && swift test --filter CloudKitSyncTests
```

**Result: `12 tests in 1 suite passed` (0 failures), ~0.036s.** Suite: `CloudKit Synchronization Ritual Trials` (`Tests/MemoryKitTests/CloudKitSyncTests.swift`). Trials exercised:

| # | Trial | Verifies |
|---|-------|----------|
| 1 | one-way push exports public/friends only | remote rows never pulled into local; only allowed visibility uploaded |
| 1b | private + internal NEVER export | fail-closed visibility cloak (`VisibilityFilter.externalReplication`) |
| 2 | sync disabled | prerequisite gate throws `.syncDisabled` |
| 3 | battery-low throttle | throws `.batteryTooLow` |
| 4 | charging overrides low battery | proceeds while charging |
| 5 | Wi-Fi restriction on cellular | throws `.wifiRequired` |
| 6 | offline darkness | throws `.networkDisconnected` |
| 7 | transient save failure recovers | retry ritual, 2 attempts → success, `isCloudDirty == false` |
| 8 | severe storm fails **OPEN** | no throw; `.failedOpen`, hot store sovereign, `isCloudDirty == true` |
| 9 | seal verifier fail-closed | `.sealVerificationFailed` blocks export, 0 save attempts |
| 10 | schema/home markers frozen | `recordType == AnimaEpisodicRecord`, `direction == .localToCloudKitPrivateDB` |
| 11 | `syncOnlyWhileCharging` gate | throws `.chargingRequired` |

All trials run against `MockCloudKitDatabase` (an in-memory `actor` conforming to `CloudKitDatabase`) and in-memory SwiftData — **no network, no real CloudKit**.

## 3. Entitlement / container state (searched both repos)

- **No app-level `.entitlements` file** exists in `~/Developer/multibrain` or `~/Developer/Andromeda`. (The only `.entitlements` hits are inside `.build/checkouts/…` for `swift-syntax` and `xctest-dynamic-overlay` example apps — irrelevant third-party artifacts.)
- **No `com.apple.developer.icloud-services`** and **no `com.apple.developer.icloud-container-identifiers`** anywhere.
- **No `CKContainer` / `privateCloudDatabase` / `containerIdentifier` / `NSUbiquitous`** references in any non-test source. `import CloudKit` appears in exactly **one** file (`CloudKitSyncEngine.swift`).
- **No real `CloudKitSyncEngine(...)` construction** outside tests — the engine is only ever instantiated with the mock DB in `CloudKitSyncTests`.
- **No `.xcodeproj` / `.xcworkspace` / app `Info.plist`.** Andromeda ships **SwiftPM executables** (`AndromedaHome`, `AndromedaHUD`, `andromeda` CLI — see `Package.swift` products), which produce bare Mach-O binaries, **not** signed `.app` bundles. Prior ad-hoc codesigning (PROOF 38) **cannot** carry iCloud entitlements — those require a provisioning profile + Developer team + provisioned container.

**Conclusion:** CloudKit is **stubbed/simulated in tests only**. No real container is configured; the real `CKDatabase` conformance exists as a seam but is never constructed or wired to a shipping surface.

## 4. Agent-verified vs human-only (honest split)

**✅ Agent-verified (done here):**
- Engine control flow: prerequisite gates (sync-disabled, offline, Wi-Fi-only, battery, charging).
- Visibility fail-closed: `private`/`internal` never leave; only `public`/`friends` export.
- Retry ritual + transient-failure recovery.
- Fail-**open** on transport storms (hot store stays sovereign, `isCloudDirty` flips).
- Seal-gate fail-**closed** (missing hash / broken seal blocks export, 0 saves).
- Schema/direction/home markers frozen (BIN-22 gate).
- One-way invariant: remote rows are never merged into local.

**🧑 Human-only (cannot be agent-verified from this tree):**
- Provisioning: create/attach an app target with iCloud + CloudKit entitlements and a `iCloud.<bundle-id>` container under an Apple Developer team.
- Sign into a real iCloud account via **System Settings → iCloud** on the test Mac.
- Observe an actual record land in the **CloudKit Dashboard** (`AnimaEpisodicRecord` in the private DB).
- Cross-device sync observation (Studio → Book/iMac satellite recall of a pushed public/friends record).
- Confirm private/internal rows are **absent** in the real container after a live push.

## 5. HUMAN checklist for the CloudKit GUI smoke (BIN-79)

Only a person at a GUI can do these. Do them in order:

1. **Provision (Xcode / Developer portal):** add/select an app target for a MemoryKit consumer, enable **iCloud → CloudKit**, create container `iCloud.com.multibrain.andromeda` (or chosen id), add the `com.apple.developer.icloud-services` + container-identifiers entitlements, sign with a real Developer team (not ad-hoc).
2. **Wire the real DB:** construct `CKContainer(identifier: "iCloud.…").privateCloudDatabase` and inject it into `CloudKitSyncEngine(ckDatabase:)` on the app path (replacing the mock used in tests).
3. **iCloud account:** on the test Mac, **System Settings → Apple Account → iCloud** → signed in, app's iCloud toggle ON, network reachable (Wi-Fi if `syncOnlyOnWifi`).
4. **Live push:** insert ≥1 `public`, ≥1 `friends`, ≥1 `private`, ≥1 `internal` `AnimaEpisodicRecord`; trigger `engine.sync()`; expect `.completed(uploaded: 2, skippedVisibility: 2)`.
5. **CloudKit Dashboard verify:** confirm only the `public` + `friends` records exist as `AnimaEpisodicRecord` in the **private** DB; confirm **no** `private`/`internal` rows leaked.
6. **Cross-device:** on a second signed-in device/satellite, confirm the pushed records recall; confirm the one-way invariant (local never mutated from remote).
7. Capture screenshots (Dashboard + System Settings iCloud pane) and append to this proof; only then may BIN-79 move to Done.

## 6. Tracking

- **BIN-79:** stays **Todo / In-Progress** — engine logic proven; real end-to-end CloudKit **not** observed (honest outcome). Human checklist above is the remaining work. *(Linear MCP was unavailable in this session — comment text prepared for operator to post; see run summary.)*
- **Multica HAB-86:** mirror — **SKIP** (Multica MCP unavailable in this session).
- No Changelog/TODO/Features/Roadmap edits. No commit. No secrets.
