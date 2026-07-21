# Sample apps — MemoryKit, Anima, Andromeda

> **Trackers:** BIN-155 epic · BIN-156…161 · HAB-146…152  
> **Run now:** MemoryKitSample + AnimaSample (macOS SPM executables)  
> **Later:** Andromeda pillar samples (HUD, Home, Gateway, CLI)

---

## Ladder

| App | Package | Status | Run |
|-----|---------|--------|-----|
| **MemoryKitSample** | `Packages/MemoryKit` | ✅ shipped | `cd Packages/MemoryKit && swift run MemoryKitSample` |
| **AnimaSample** | `Packages/Anima` | ✅ shipped | `cd Packages/Anima && swift run AnimaSample` |
| **AndromedaHUDSample** | root / Xcode | 📐 BIN-158 | pairs with BIN-153 signed `.app` |
| **AndromedaHomeSample** | root | 📐 BIN-159 | HomeCore console |
| **AndromedaGatewaySample** | root | 📐 BIN-160 | Autocache / LLM proxy demo |
| **AndromedaCLISample** | root | 📐 BIN-161 | fleet observe + install walkthrough |

---

## MemoryKitSample (BIN-156)

Demonstrates the **hot spine only**:

- `CaptureService.storeMemory` → in-memory SwiftData
- `RetrievalService.recallMemory` → hot hits (vault fallback off)
- Merkle seal preview when ledger enabled

No Anima, no Andromeda, no indexes.

---

## AnimaSample (BIN-157)

Demonstrates **Phase 1 Anima modules**:

| Tab | Module | Demo |
|-----|--------|------|
| TCA Core | AnimaCore | `MemoryReducer` sync / health / visibility |
| Knowledge | AnimaKnowledge | seed hot + `ObsidianMaterializer.materializePending` → `/tmp` vault |
| Indexing | AnimaIndexing | HTTP probe Ladybug `:8286/health` |

---

## Andromeda samples (tickets only — implement after MemoryKit/Anima dogfood)

- **HUD** — daily vault recall dogfood; signed bundle (BIN-158 + BIN-153)
- **Home** — memory console + `project.state` panel (BIN-159)
- **Gateway** — Hummingbird Autocache soak (BIN-160)
- **CLI** — `andromeda` + LaunchEntity roster tour (BIN-161)

Existing executables (`swift run AndromedaHUD`, `AndromedaHome`, `andromeda`) are dev paths — sample apps add UX labels, fixture modes, and README entry points for contributors.

---

## Related

- [SWIFT-PACKAGE-HIERARCHY.md](./SWIFT-PACKAGE-HIERARCHY.md)
- [ANIMA-PROJECT-LINKS.md](./ANIMA-PROJECT-LINKS.md)
