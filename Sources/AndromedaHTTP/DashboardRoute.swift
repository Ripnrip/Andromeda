import AndromedaDomain
import AndromedaMemory
import Foundation
import HTTPTypes
import Hummingbird

/**
 * 🎭 The DashboardRoute — Projection Viewport of the Runtime Journal
 *
 * "A glass port on the near-black void: humans journal memories here;
 *  agents later recall them across the field. Canonical truth stays
 *  in the event journal — this page is only starlight reflecting back."
 *
 * - The Spellbinding Museum Director of Runtime Consoles
 */
public struct DashboardRoute: Sendable {
    /// 🌌 Shared memory runtime that powers list/recall proxying.
    private let memoryRuntime: MemoryRuntime

    /// 🌟 Demo project scope shared with the embedded console UI.
    /// Keep in lockstep with `dashboardHTML`'s `DEMO_PROJECT_ID` constant.
    public static let demoProjectID = ProjectID(
        rawValue: UUID(uuidString: "d0a7b0a1-d000-4000-8000-c0ffee000001")!
    )

    // 🎨 Wire the memory runtime — same injection style as RuntimeRouter.
    public init(memoryRuntime: MemoryRuntime) {
        self.memoryRuntime = memoryRuntime
    }

    /// 🌐 Register the human-facing dashboard + memories list onto an existing router.
    ///
    /// Matches Hummingbird 2.x `Router.get` patterns used by `RuntimeRouter`.
    /// The generic `Context` keeps this composable with any `RequestContext`.
    public func register<Context: RequestContext>(on router: Router<Context>) {
        let memoryRuntime = self.memoryRuntime

        // 🏠 Root — serve the single-file memory console projection.
        router.get("/") { _, _ -> Response in
            Self.htmlResponse(Self.dashboardHTML)
        }

        // 📜 Lightweight list endpoint: proxies recall for a project scope.
        router.get("/v1/memories") { request, _ -> Response in
            do {
                let queryItems = request.uri.queryParameters
                guard
                    let projectRaw = queryItems.get("projectID"),
                    let projectUUID = UUID(uuidString: projectRaw)
                else {
                    throw AndromedaRuntimeError.invalidRuntimeRequest(
                        "Query parameter projectID must be a valid UUID."
                    )
                }

                let limit: Int
                if let limitRaw = queryItems.get("limit"), let parsed = Int(limitRaw) {
                    limit = parsed
                } else {
                    limit = 20
                }

                // Broad query: scoring always applies a recency bonus, so every
                // in-scope record surfaces; limit + privacy ceiling still apply.
                let recallRequest = RecallRequest(
                    query: "memory",
                    purpose: "dashboard.list",
                    scope: EventScope(projectID: ProjectID(rawValue: projectUUID)),
                    privacyCeiling: .project,
                    resultLimit: max(1, limit),
                    kinds: [],
                    fileContext: [],
                    symbolContext: [],
                    taskContext: []
                )
                let response = try await memoryRuntime.recall(recallRequest)
                return try Self.encodeJSON(response)
            } catch {
                return Self.errorResponse(for: error)
            }
        }
    }

    // MARK: - Response helpers (mirrors RuntimeRouter alchemy)

    // 🎁 Wrap HTML starlight in a proper content-type envelope.
    private static func htmlResponse(_ html: String) -> Response {
        var headers = HTTPFields()
        headers[.contentType] = "text/html; charset=utf-8"
        return Response(
            status: .ok,
            headers: headers,
            body: .init(byteBuffer: .init(string: html))
        )
    }

    // 💎 Encode JSON the same way RuntimeRouter does — no date strategy surprises.
    private static func encodeJSON(_ value: some Encodable) throws -> Response {
        let data = try JSONEncoder().encode(value)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok,
            headers: headers,
            body: .init(byteBuffer: .init(data: data))
        )
    }

    // 🌩️ Map domain errors to typed HTTP storms (400 vs 500).
    private static func errorResponse(for error: Error) -> Response {
        let runtimeError = error as? AndromedaRuntimeError
        let status: HTTPResponse.Status
        switch runtimeError {
        case .invalidMemoryContent, .invalidRecallQuery, .invalidRuntimeRequest:
            status = .badRequest
        case .none:
            status = .internalServerError
        default:
            status = .internalServerError
        }

        let payload: [String: String] = [
            "error": runtimeError?.localizedDescription ?? error.localizedDescription,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: status,
            headers: headers,
            body: .init(byteBuffer: .init(data: data))
        )
    }

    // MARK: - Embedded dashboard (single-file projection)

    /// 🛰️ The full Runtime Memory Console — system fonts, inline CSS/JS, zero external assets.
    static let dashboardHTML: String = #"""
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Andromeda Runtime Memory Console</title>
<style>
  :root {
    --void: #0a0e1a;
    --void-2: #0d1224;
    --glass: rgba(255, 255, 255, 0.04);
    --glass-border: rgba(255, 255, 255, 0.10);
    --glass-hover: rgba(255, 255, 255, 0.07);
    --text: #e8eaf2;
    --muted: #8b93a7;
    --indigo: #6366f1;
    --violet: #a855f7;
    --gradient: linear-gradient(135deg, #6366f1 0%, #a855f7 100%);
    --ok: #34d399;
    --warn: #fbbf24;
    --bad: #f87171;
    --mono: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
    --sans: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", system-ui, sans-serif;
    --radius: 14px;
    --shadow: 0 8px 32px rgba(0, 0, 0, 0.35);
  }

  * { box-sizing: border-box; }
  html, body {
    margin: 0; padding: 0; min-height: 100%;
    background: var(--void);
    color: var(--text);
    font-family: var(--sans);
    font-size: 15px;
    line-height: 1.5;
  }

  /* ✨ Zero-JS starfield — pure CSS radial-gradient dust */
  body {
    background-color: var(--void);
    background-image:
      radial-gradient(1px 1px at 12% 18%, rgba(255,255,255,0.55), transparent),
      radial-gradient(1px 1px at 28% 72%, rgba(255,255,255,0.35), transparent),
      radial-gradient(1.2px 1.2px at 44% 34%, rgba(255,255,255,0.45), transparent),
      radial-gradient(1px 1px at 61% 12%, rgba(255,255,255,0.30), transparent),
      radial-gradient(1px 1px at 73% 58%, rgba(255,255,255,0.50), transparent),
      radial-gradient(1.2px 1.2px at 88% 26%, rgba(255,255,255,0.40), transparent),
      radial-gradient(1px 1px at 15% 88%, rgba(255,255,255,0.28), transparent),
      radial-gradient(1px 1px at 52% 90%, rgba(255,255,255,0.38), transparent),
      radial-gradient(1.5px 1.5px at 95% 80%, rgba(168,85,247,0.35), transparent),
      radial-gradient(1.5px 1.5px at 8% 48%, rgba(99,102,241,0.30), transparent),
      radial-gradient(800px 400px at 20% -10%, rgba(99,102,241,0.12), transparent),
      radial-gradient(600px 300px at 90% 110%, rgba(168,85,247,0.10), transparent);
    background-attachment: fixed;
  }

  .shell {
    max-width: 1180px;
    margin: 0 auto;
    padding: 28px 22px 48px;
  }

  /* Header */
  header.top {
    display: flex;
    flex-wrap: wrap;
    align-items: flex-start;
    justify-content: space-between;
    gap: 16px;
    margin-bottom: 28px;
  }
  .wordmark {
    font-size: 1.65rem;
    font-weight: 700;
    letter-spacing: 0.18em;
    background: var(--gradient);
    -webkit-background-clip: text;
    background-clip: text;
    color: transparent;
    margin: 0 0 4px;
  }
  .subtitle {
    color: var(--muted);
    font-size: 0.92rem;
    margin: 0;
  }
  .health-pill {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 8px 14px;
    border-radius: 999px;
    background: var(--glass);
    border: 1px solid var(--glass-border);
    backdrop-filter: blur(12px);
    -webkit-backdrop-filter: blur(12px);
    font-size: 0.82rem;
    color: var(--muted);
    box-shadow: var(--shadow);
  }
  .health-dot {
    width: 8px; height: 8px; border-radius: 50%;
    background: var(--muted);
    box-shadow: 0 0 0 0 transparent;
  }
  .health-dot.ok {
    background: var(--ok);
    box-shadow: 0 0 10px rgba(52, 211, 153, 0.65);
  }
  .health-dot.bad {
    background: var(--bad);
    box-shadow: 0 0 10px rgba(248, 113, 113, 0.55);
  }
  .health-version { font-family: var(--mono); font-size: 0.78rem; color: var(--text); }

  /* Grid */
  .grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 20px;
  }
  @media (max-width: 900px) {
    .grid { grid-template-columns: 1fr; }
  }

  .card {
    background: var(--glass);
    border: 1px solid var(--glass-border);
    border-radius: var(--radius);
    backdrop-filter: blur(16px);
    -webkit-backdrop-filter: blur(16px);
    padding: 22px;
    box-shadow: var(--shadow);
  }
  .card h2 {
    margin: 0 0 6px;
    font-size: 1.05rem;
    font-weight: 600;
    letter-spacing: 0.02em;
  }
  .card .hint {
    color: var(--muted);
    font-size: 0.82rem;
    margin: 0 0 18px;
  }

  label.field {
    display: block;
    margin-bottom: 14px;
  }
  label.field > span {
    display: block;
    font-size: 0.75rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--muted);
    margin-bottom: 6px;
  }
  input[type="text"], textarea {
    width: 100%;
    background: rgba(0,0,0,0.28);
    border: 1px solid var(--glass-border);
    border-radius: 10px;
    color: var(--text);
    padding: 10px 12px;
    font-family: inherit;
    font-size: 0.95rem;
    outline: none;
    transition: border-color 0.15s ease;
  }
  input[type="text"]:focus, textarea:focus {
    border-color: rgba(99,102,241,0.55);
  }
  textarea { min-height: 120px; resize: vertical; line-height: 1.45; }

  .segmented {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
  }
  .segmented button {
    background: rgba(0,0,0,0.25);
    border: 1px solid var(--glass-border);
    color: var(--muted);
    border-radius: 8px;
    padding: 6px 11px;
    font-size: 0.78rem;
    cursor: pointer;
    transition: all 0.12s ease;
  }
  .segmented button:hover { background: var(--glass-hover); color: var(--text); }
  .segmented button.active {
    color: var(--text);
    border-color: rgba(99,102,241,0.55);
    background: linear-gradient(135deg, rgba(99,102,241,0.25), rgba(168,85,247,0.22));
  }

  .privacy-grid {
    display: grid;
    gap: 8px;
  }
  .privacy-option {
    display: flex;
    gap: 10px;
    align-items: flex-start;
    padding: 10px 12px;
    border-radius: 10px;
    border: 1px solid var(--glass-border);
    background: rgba(0,0,0,0.18);
    cursor: pointer;
  }
  .privacy-option.active {
    border-color: rgba(99,102,241,0.5);
    background: linear-gradient(135deg, rgba(99,102,241,0.12), rgba(168,85,247,0.10));
  }
  .privacy-option input { margin-top: 3px; accent-color: var(--indigo); }
  .privacy-option strong { display: block; font-size: 0.88rem; }
  .privacy-option small { color: var(--muted); font-size: 0.78rem; }

  .demo-scope {
    font-family: var(--mono);
    font-size: 0.72rem;
    color: var(--muted);
    background: rgba(0,0,0,0.25);
    border-radius: 8px;
    padding: 8px 10px;
    margin-bottom: 14px;
    word-break: break-all;
  }
  .demo-scope b { color: var(--text); font-weight: 500; }

  .btn-commit {
    width: 100%;
    margin-top: 8px;
    border: none;
    border-radius: 12px;
    padding: 14px 18px;
    font-size: 0.95rem;
    font-weight: 600;
    letter-spacing: 0.01em;
    color: white;
    background: var(--gradient);
    cursor: pointer;
    box-shadow: 0 6px 24px rgba(99,102,241,0.35);
    transition: transform 0.12s ease, box-shadow 0.12s ease, opacity 0.12s ease;
  }
  .btn-commit:hover:not(:disabled) {
    transform: translateY(-1px);
    box-shadow: 0 10px 28px rgba(168,85,247,0.40);
  }
  .btn-commit:disabled { opacity: 0.55; cursor: not-allowed; }

  .receipt {
    margin-top: 16px;
    padding: 14px;
    border-radius: 12px;
    border: 1px solid rgba(99,102,241,0.30);
    background: rgba(99,102,241,0.08);
    display: none;
  }
  .receipt.visible { display: block; }
  .receipt h3 {
    margin: 0 0 10px;
    font-size: 0.85rem;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    color: var(--muted);
  }
  .badge {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    padding: 3px 9px;
    border-radius: 999px;
    font-size: 0.72rem;
    font-weight: 600;
    letter-spacing: 0.03em;
    text-transform: uppercase;
  }
  .badge.ok { background: rgba(52,211,153,0.15); color: var(--ok); border: 1px solid rgba(52,211,153,0.30); }
  .badge.warn { background: rgba(251,191,36,0.12); color: var(--warn); border: 1px solid rgba(251,191,36,0.28); }
  .badge.bad { background: rgba(248,113,113,0.12); color: var(--bad); border: 1px solid rgba(248,113,113,0.28); }
  .badge.kind-decision { background: rgba(99,102,241,0.18); color: #a5b4fc; }
  .badge.kind-discovery { background: rgba(34,211,238,0.14); color: #67e8f9; }
  .badge.kind-workflow { background: rgba(52,211,153,0.14); color: #6ee7b7; }
  .badge.kind-issue { background: rgba(248,113,113,0.14); color: #fca5a5; }
  .badge.kind-checkpoint { background: rgba(251,191,36,0.14); color: #fcd34d; }
  .badge.kind-note { background: rgba(168,85,247,0.16); color: #d8b4fe; }
  .badge.privacy { background: rgba(255,255,255,0.06); color: var(--muted); border: 1px solid var(--glass-border); }

  .sink-list { list-style: none; padding: 0; margin: 10px 0 0; }
  .sink-list li {
    font-family: var(--mono);
    font-size: 0.75rem;
    padding: 8px 0;
    border-top: 1px solid rgba(255,255,255,0.06);
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    align-items: center;
  }
  .btn-ghost {
    background: transparent;
    border: 1px solid var(--glass-border);
    color: var(--text);
    border-radius: 8px;
    padding: 6px 10px;
    font-size: 0.75rem;
    cursor: pointer;
  }
  .btn-ghost:hover { background: var(--glass-hover); }

  /* Memory field */
  .search-row {
    display: flex;
    gap: 8px;
    margin-bottom: 12px;
  }
  .search-row input { flex: 1; }
  .chips { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 14px; }
  .chip {
    border: 1px solid var(--glass-border);
    background: rgba(0,0,0,0.2);
    color: var(--muted);
    border-radius: 999px;
    padding: 5px 12px;
    font-size: 0.75rem;
    cursor: pointer;
  }
  .chip.active, .chip:hover {
    color: var(--text);
    border-color: rgba(168,85,247,0.45);
    background: rgba(168,85,247,0.12);
  }
  .chip.flagship {
    border-color: rgba(168,85,247,0.45);
    color: #e9d5ff;
  }

  .results { display: flex; flex-direction: column; gap: 10px; min-height: 120px; }
  .empty-state {
    color: var(--muted);
    font-size: 0.88rem;
    text-align: center;
    padding: 28px 12px;
  }
  .hit {
    padding: 14px;
    border-radius: 12px;
    border: 1px solid var(--glass-border);
    background: rgba(0,0,0,0.22);
  }
  .hit .summary {
    font-size: 0.95rem;
    margin: 0 0 8px;
    word-break: break-word;
  }
  .hit-meta {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    align-items: center;
    margin-bottom: 8px;
  }
  .hit-tags {
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
    margin-bottom: 6px;
  }
  .tag {
    font-size: 0.7rem;
    padding: 2px 7px;
    border-radius: 6px;
    background: rgba(255,255,255,0.05);
    color: var(--muted);
    font-family: var(--mono);
  }
  .hit-foot {
    font-family: var(--mono);
    font-size: 0.7rem;
    color: var(--muted);
    display: flex;
    flex-wrap: wrap;
    gap: 10px;
  }

  /* Secrets strip */
  .secrets {
    margin-top: 20px;
    display: flex;
    gap: 14px;
    align-items: flex-start;
    opacity: 0.72;
    pointer-events: none;
    user-select: none;
  }
  .secrets .lock {
    font-size: 1.4rem;
    line-height: 1;
    filter: grayscale(0.3);
  }
  .secrets h2 { margin: 0 0 4px; font-size: 0.95rem; }
  .secrets p { margin: 0; color: var(--muted); font-size: 0.85rem; }
  .secrets .scoped-badge {
    display: inline-block;
    margin-top: 8px;
    font-size: 0.7rem;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: var(--muted);
    border: 1px dashed var(--glass-border);
    border-radius: 6px;
    padding: 3px 8px;
  }

  footer.foot {
    margin-top: 28px;
    text-align: center;
    color: var(--muted);
    font-size: 0.78rem;
    letter-spacing: 0.02em;
  }

  /* Toasts */
  #toasts {
    position: fixed;
    right: 16px;
    bottom: 16px;
    z-index: 1000;
    display: flex;
    flex-direction: column;
    gap: 8px;
    max-width: min(380px, calc(100vw - 32px));
  }
  .toast {
    background: rgba(20, 24, 40, 0.92);
    border: 1px solid rgba(248,113,113,0.35);
    color: var(--text);
    border-radius: 12px;
    padding: 12px 14px;
    font-size: 0.85rem;
    box-shadow: var(--shadow);
    backdrop-filter: blur(12px);
    animation: toast-in 0.2s ease;
  }
  .toast.ok { border-color: rgba(52,211,153,0.35); }
  @keyframes toast-in {
    from { opacity: 0; transform: translateY(8px); }
    to { opacity: 1; transform: translateY(0); }
  }
</style>
</head>
<body>
<div class="shell">
  <header class="top">
    <div>
      <h1 class="wordmark">ANDROMEDA</h1>
      <p class="subtitle">Runtime Memory Console — projection view</p>
    </div>
    <div class="health-pill" id="healthPill" title="Live runtime health">
      <span class="health-dot" id="healthDot"></span>
      <span id="healthStatus">checking…</span>
      <span class="health-version" id="healthVersion"></span>
    </div>
  </header>

  <div class="grid">
    <!-- LEFT: Journal -->
    <section class="card" aria-labelledby="journal-title">
      <h2 id="journal-title">Journal a memory</h2>
      <p class="hint">Write into the canonical event journal. Projections may lag — the journal never blocks on them.</p>

      <div class="demo-scope">
        <b>Demo project scope</b><br/>
        projectID = <span id="demoProjectLabel"></span>
      </div>

      <label class="field">
        <span>Who are you</span>
        <input type="text" id="viewerIdentity" placeholder="viewer identity label" autocomplete="username"/>
      </label>

      <label class="field">
        <span>Memory content</span>
        <textarea id="content" placeholder="What should the fleet remember?"></textarea>
      </label>

      <label class="field">
        <span>Kind</span>
        <div class="segmented" id="kindPicker" role="group" aria-label="Memory kind"></div>
      </label>

      <label class="field">
        <span>Privacy</span>
        <div class="privacy-grid" id="privacyPicker"></div>
      </label>

      <label class="field">
        <span>Tags (comma-separated)</span>
        <input type="text" id="tags" placeholder="jokes, runtime, demo"/>
      </label>

      <button type="button" class="btn-commit" id="commitBtn">Commit to canonical memory</button>

      <div class="receipt" id="receiptPanel">
        <h3>Write receipt</h3>
        <div id="receiptBody"></div>
      </div>
    </section>

    <!-- RIGHT: Memory field -->
    <section class="card" aria-labelledby="field-title">
      <h2 id="field-title">Memory field</h2>
      <p class="hint">Search the operational projection — same scope, privacy ceiling <code style="font-family:var(--mono);font-size:0.8em">project</code>.</p>

      <div class="search-row">
        <input type="text" id="search" placeholder="Search memories…" aria-label="Search memories"/>
      </div>
      <div class="chips">
        <button type="button" class="chip flagship" id="jokesChip" title="Flagship demo: human journals a joke; guest VM agent recalls it">jokes</button>
        <button type="button" class="chip" data-quick="decision">decision</button>
        <button type="button" class="chip" data-quick="discovery">discovery</button>
        <button type="button" class="chip" data-quick="note">note</button>
      </div>
      <div class="results" id="results">
        <div class="empty-state">Search the field — or try the jokes chip for the flagship demo path.</div>
      </div>
    </section>
  </div>

  <!-- BOTTOM: Secrets (scoped / future) -->
  <section class="card secrets" aria-disabled="true">
    <div class="lock" aria-hidden="true">🔒</div>
    <div>
      <h2>Secrets</h2>
      <p>Secrets broker lands in M5 — scoped views coming. The journal never blocks on projections.</p>
      <span class="scoped-badge">scoped · disabled · m5</span>
    </div>
  </section>

  <footer class="foot">
    Andromeda Runtime v2 · this page is a projection — canonical truth lives in the event journal.
  </footer>
</div>

<div id="toasts" aria-live="polite"></div>

<script>
(function () {
  // 🌌 Fixed demo project — must match DashboardRoute.demoProjectID
  const DEMO_PROJECT_ID = "d0a7b0a1-d000-4000-8000-c0ffee000001";

  // Contract pins: UI talks only to these memory paths.
  const PATH_REMEMBER = "/v1/memory/remember";
  const PATH_RECALL = "/v1/memory/recall";
  const PATH_HEALTH = "/health";

  const KINDS = ["decision", "discovery", "workflow", "issue", "checkpoint", "note"];
  const PRIVACY = [
    { id: "public", label: "public", blurb: "Visible across the fleet — no project fence." },
    { id: "project", label: "project", blurb: "Scoped to this demo project — default for collaboration." },
    { id: "private", label: "private", blurb: "Session/user private — not shown under project ceiling." },
  ];

  const LS_VIEWER = "andromeda.dashboard.viewerIdentity";

  let selectedKind = "note";
  let selectedPrivacy = "project";
  let searchTimer = null;
  let lastRememberBody = null;

  const $ = (id) => document.getElementById(id);

  // ── Typed ID helpers (Swift Codable shapes) ──────────────────────────
  // UUID-backed IDs encode as {"rawValue":"<uuid>"}; IdempotencyKey is a plain string.
  function typedUUID(uuid) {
    return { rawValue: uuid };
  }

  function buildScope(sessionID) {
    const scope = { projectID: typedUUID(DEMO_PROJECT_ID) };
    if (sessionID) scope.sessionID = typedUUID(sessionID);
    return scope;
  }

  function newIdempotencyKey() {
    if (crypto.randomUUID) return crypto.randomUUID();
    return "dashboard-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 10);
  }

  // Swift JSONEncoder default Date = seconds since 2001-01-01 reference date.
  function formatSwiftDate(value) {
    if (value == null) return "—";
    if (typeof value === "number") {
      const refMs = Date.UTC(2001, 0, 1);
      return new Date(refMs + value * 1000).toLocaleString();
    }
    const d = new Date(value);
    return Number.isNaN(d.getTime()) ? String(value) : d.toLocaleString();
  }

  function truncateChecksum(checksum) {
    if (!checksum) return "—";
    const hex = String(checksum).replace(/^sha256:/i, "");
    const short = hex.slice(0, 12);
    return (String(checksum).startsWith("sha256:") ? "sha256:" : "") + short + (hex.length > 12 ? "…" : "");
  }

  function rawOf(typed) {
    if (typed == null) return "";
    if (typeof typed === "string") return typed;
    if (typeof typed === "object" && typed.rawValue != null) return String(typed.rawValue);
    return String(typed);
  }

  // ── Toasts ───────────────────────────────────────────────────────────
  function toast(message, ok) {
    const el = document.createElement("div");
    el.className = "toast" + (ok ? " ok" : "");
    el.textContent = message;
    $("toasts").appendChild(el);
    setTimeout(() => el.remove(), 5200);
  }

  async function readError(res) {
    try {
      const j = await res.json();
      if (j && j.error) return j.error;
      return JSON.stringify(j);
    } catch (_) {
      try { return await res.text(); } catch (e) { return res.statusText || "Request failed"; }
    }
  }

  // ── Health pill ──────────────────────────────────────────────────────
  async function refreshHealth() {
    try {
      const res = await fetch(PATH_HEALTH);
      if (!res.ok) throw new Error(await readError(res));
      const data = await res.json();
      $("healthDot").className = "health-dot " + (data.status === "healthy" ? "ok" : "bad");
      $("healthStatus").textContent = data.status || "unknown";
      $("healthVersion").textContent = data.version ? "· " + data.version : "";
    } catch (err) {
      $("healthDot").className = "health-dot bad";
      $("healthStatus").textContent = "unreachable";
      $("healthVersion").textContent = "";
    }
  }

  // ── Kind / privacy pickers ───────────────────────────────────────────
  function renderKindPicker() {
    const root = $("kindPicker");
    root.innerHTML = "";
    KINDS.forEach((k) => {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.textContent = k;
      btn.className = k === selectedKind ? "active" : "";
      btn.addEventListener("click", () => {
        selectedKind = k;
        renderKindPicker();
      });
      root.appendChild(btn);
    });
  }

  function renderPrivacyPicker() {
    const root = $("privacyPicker");
    root.innerHTML = "";
    PRIVACY.forEach((p) => {
      const row = document.createElement("label");
      row.className = "privacy-option" + (p.id === selectedPrivacy ? " active" : "");
      row.innerHTML =
        '<input type="radio" name="privacy" value="' + p.id + '"' +
        (p.id === selectedPrivacy ? " checked" : "") + "/>" +
        "<div><strong>" + p.label + "</strong><small>" + p.blurb + "</small></div>";
      row.querySelector("input").addEventListener("change", () => {
        selectedPrivacy = p.id;
        renderPrivacyPicker();
      });
      root.appendChild(row);
    });
  }

  // ── Remember ─────────────────────────────────────────────────────────
  async function commitMemory() {
    const content = $("content").value;
    const actor = ($("viewerIdentity").value || "").trim() || "anonymous-viewer";
    const tags = ($("tags").value || "")
      .split(",")
      .map((t) => t.trim())
      .filter(Boolean);

    localStorage.setItem(LS_VIEWER, actor);

    const body = {
      scope: buildScope(),
      source: {
        subsystem: "dashboard",
        actor: actor,
        label: "runtime-console",
      },
      content: content,
      kind: selectedKind,
      privacyLevel: selectedPrivacy,
      tags: tags,
      metadata: {},
      idempotencyKey: newIdempotencyKey(),
      relatedContext: {},
    };
    lastRememberBody = body;

    const btn = $("commitBtn");
    btn.disabled = true;
    try {
      const res = await fetch(PATH_REMEMBER, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      if (!res.ok) {
        const msg = await readError(res);
        toast((res.status === 400 ? "400: " : res.status + ": ") + msg, false);
        return;
      }
      const receipt = await res.json();
      renderReceipt(receipt);
      toast("Memory committed to the journal.", true);
      // Soft-refresh field with current query if any.
      const q = $("search").value.trim();
      if (q) runRecall(q, []);
    } catch (err) {
      toast(String(err && err.message ? err.message : err), false);
    } finally {
      btn.disabled = false;
    }
  }

  function verificationBadge(status) {
    const s = status || "unsupported";
    const cls = s === "verified" ? "ok" : s === "failed" ? "bad" : "warn";
    const icon = s === "verified" ? "✓" : s === "failed" ? "!" : "…";
    return '<span class="badge ' + cls + '">' + icon + " " + s + "</span>";
  }

  function statusBadge(status) {
    const s = status || "unknown";
    const cls = s === "committed" ? "ok" : s === "skipped" ? "warn" : "bad";
    return '<span class="badge ' + cls + '">' + s + "</span>";
  }

  function renderReceipt(receipt) {
    const panel = $("receiptPanel");
    const body = $("receiptBody");
    const sinks = (receipt.sinkReceipts || [])
      .map(function (s) {
        return (
          "<li>" +
          "<span>" + (s.sinkID || "sink") + "</span>" +
          "<span>" + truncateChecksum(s.checksum) + "</span>" +
          statusBadge(s.status) +
          verificationBadge(s.verification) +
          "</li>"
        );
      })
      .join("");

    body.innerHTML =
      "<div class=\"hit-meta\">" +
      verificationBadge(receipt.verificationStatus) +
      "<span class=\"badge privacy\">retry: " + (receipt.retryStatus || "none") + "</span>" +
      "</div>" +
      "<div class=\"hit-foot\" style=\"margin:8px 0\">" +
      "<span>memoryID " + rawOf(receipt.memoryID) + "</span>" +
      "<span>eventID " + rawOf(receipt.eventID) + "</span>" +
      "<span>corr " + (receipt.correlationID || "") + "</span>" +
      "</div>" +
      (sinks ? "<ul class=\"sink-list\">" + sinks + "</ul>" : "") +
      "<div style=\"margin-top:12px\">" +
      "<button type=\"button\" class=\"btn-ghost\" id=\"copyCurlBtn\">Copy as curl</button>" +
      "</div>";

    panel.classList.add("visible");
    const copyBtn = $("copyCurlBtn");
    if (copyBtn) {
      copyBtn.addEventListener("click", function () {
        const payload = lastRememberBody || {};
        const curl =
          "curl -sS -X POST '" + location.origin + PATH_REMEMBER + "' \\\n" +
          "  -H 'Content-Type: application/json' \\\n" +
          "  -d " + JSON.stringify(JSON.stringify(payload));
        navigator.clipboard.writeText(curl).then(
          function () { toast("curl copied to clipboard.", true); },
          function () { toast("Could not copy curl.", false); }
        );
      });
    }
  }

  // ── Recall ───────────────────────────────────────────────────────────
  async function runRecall(query, kinds) {
    const q = (query || "").trim();
    if (!q) {
      $("results").innerHTML =
        '<div class="empty-state">Search the field — or try the jokes chip for the flagship demo path.</div>';
      return;
    }

    const body = {
      query: q,
      purpose: "dashboard.search",
      scope: buildScope(),
      privacyCeiling: "project",
      resultLimit: 10,
      kinds: kinds || [],
      fileContext: [],
      symbolContext: [],
      taskContext: [],
    };

    $("results").innerHTML = '<div class="empty-state">Searching the field…</div>';
    try {
      const res = await fetch(PATH_RECALL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      if (!res.ok) {
        const msg = await readError(res);
        toast((res.status === 400 ? "400: " : res.status + ": ") + msg, false);
        $("results").innerHTML = '<div class="empty-state">Recall failed.</div>';
        return;
      }
      const data = await res.json();
      renderHits(data.records || []);
    } catch (err) {
      toast(String(err && err.message ? err.message : err), false);
      $("results").innerHTML = '<div class="empty-state">Recall failed.</div>';
    }
  }

  function renderHits(hits) {
    const root = $("results");
    if (!hits.length) {
      root.innerHTML = '<div class="empty-state">No matching memory records in this projection.</div>';
      return;
    }
    root.innerHTML = hits
      .map(function (hit) {
        const rec = hit.record || {};
        const prov = hit.provenance || {};
        const tags = (rec.tags || [])
          .map(function (t) { return '<span class="tag">' + escapeHtml(t) + "</span>"; })
          .join("");
        const kind = rec.kind || "note";
        return (
          '<article class="hit">' +
          '<p class="summary">' + escapeHtml(rec.summary || rec.content || "") + "</p>" +
          '<div class="hit-meta">' +
          '<span class="badge kind-' + kind + '">' + kind + "</span>" +
          '<span class="badge privacy">' + (rec.privacyLevel || "") + "</span>" +
          verificationBadge(prov.checksum ? "verified" : (rec.checksum ? "verified" : "pending")) +
          "</div>" +
          (tags ? '<div class="hit-tags">' + tags + "</div>" : "") +
          '<div class="hit-foot">' +
          "<span>" + escapeHtml(formatSwiftDate(rec.createdAt)) + "</span>" +
          "<span>corr " + escapeHtml(String(prov.correlationID || rec.correlationID || "")) + "</span>" +
          "<span>score " + (typeof hit.score === "number" ? hit.score.toFixed(2) : "—") + "</span>" +
          "</div>" +
          "</article>"
        );
      })
      .join("");
  }

  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function debounceSearch() {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(function () {
      runRecall($("search").value, []);
    }, 320);
  }

  // ── Boot ─────────────────────────────────────────────────────────────
  function boot() {
    $("demoProjectLabel").textContent = DEMO_PROJECT_ID;
    const saved = localStorage.getItem(LS_VIEWER);
    if (saved) $("viewerIdentity").value = saved;

    renderKindPicker();
    renderPrivacyPicker();
    refreshHealth();
    setInterval(refreshHealth, 15000);

    $("commitBtn").addEventListener("click", commitMemory);
    $("search").addEventListener("input", debounceSearch);

    $("jokesChip").addEventListener("click", function () {
      $("search").value = "jokes";
      document.querySelectorAll(".chip").forEach(function (c) { c.classList.remove("active"); });
      $("jokesChip").classList.add("active");
      // Flagship path: kind=note tagged jokes
      runRecall("jokes", ["note"]);
    });

    document.querySelectorAll(".chip[data-quick]").forEach(function (chip) {
      chip.addEventListener("click", function () {
        const k = chip.getAttribute("data-quick");
        document.querySelectorAll(".chip").forEach(function (c) { c.classList.remove("active"); });
        chip.classList.add("active");
        $("search").value = k;
        runRecall(k, [k]);
      });
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
</script>
</body>
</html>
"""#
}
