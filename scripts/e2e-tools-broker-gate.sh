#!/usr/bin/env bash
# e2e-tools-broker-gate.sh — BIN-210 live keyless e2e gate for the M4 tools/MCP broker.
#
# Proves the third brokered pillar end to end on the real fleet:
#   1. Host seeds a GitHub token into Keychain (from `gh auth token`, never printed).
#   2. Andromeda runtime boots with the MCP route enabled (bound to the tailnet IP only).
#   3. The agent-habitat VM — with zero GitHub credentials in env or config — calls
#      andromeda_github_get_me over the tailnet and gets a real answer.
#   4. Policy gate: a write attempt without --automation-allowed is denied.
#   5. Redaction: the token value never appears in anything returned.
#
# Usage:
#   LIVE_TOOLS_E2E=1 scripts/e2e-tools-broker-gate.sh
#
# Overrides: VM_SSH_HOST (default agent-habitat), E2E_PORT (default 8897).
# Cleanup is automatic (server killed, Keychain entry deleted) via trap.

set -euo pipefail

if [[ "${LIVE_TOOLS_E2E:-0}" != "1" ]]; then
  echo "SKIP: set LIVE_TOOLS_E2E=1 to run the live gate (touches Keychain + network)."
  exit 0
fi

VM_SSH_HOST="${VM_SSH_HOST:-agent-habitat}"
E2E_PORT="${E2E_PORT:-8897}"
KEYCHAIN_SERVICE="andromeda.e2e.github"
KEYCHAIN_ACCOUNT="token"
BROKER_TOKEN="e2e-broker-$(date +%s)"
WORKDIR="$(mktemp -d /tmp/andromeda-tools-e2e.XXXXXX)"
SERVER_LOG="$WORKDIR/server.log"
SERVER_PID=""
PASS=0
FAIL=0

ok()   { PASS=$((PASS+1)); echo "PASS: $1"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL: $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi }

cleanup() {
  [[ -n "$SERVER_PID" ]] && kill "$SERVER_PID" 2>/dev/null || true
  security delete-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" >/dev/null 2>&1 || true
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

echo "=== M4 tools broker live e2e gate ==="

# --- Preflight ---------------------------------------------------------------
GH_TOKEN="$(gh auth token 2>/dev/null || true)"
[[ -n "$GH_TOKEN" ]] || { echo "FAIL: gh auth token unavailable"; exit 1; }
GH_USER="$(gh api user --jq .login 2>/dev/null || true)"
[[ -n "$GH_USER" ]] || { echo "FAIL: gh api user failed"; exit 1; }
ok "host gh auth available (login: $GH_USER)"

TAILNET_IP="$(tailscale ip -4 2>/dev/null | head -1)"
[[ -n "$TAILNET_IP" ]] || { echo "FAIL: no tailscale IPv4"; exit 1; }
ok "tailnet IP: $TAILNET_IP"

if nc -z localhost "$E2E_PORT" 2>/dev/null; then
  echo "FAIL: port $E2E_PORT already in use"; exit 1
fi
ok "port $E2E_PORT free"

ssh -o ConnectTimeout=5 -o BatchMode=yes "$VM_SSH_HOST" true 2>/dev/null \
  && ok "VM reachable ($VM_SSH_HOST)" || { echo "FAIL: VM unreachable"; exit 1; }

# --- Seed Keychain (host-side secret; VM never sees it) ----------------------
security add-generic-password -U -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w "$GH_TOKEN" >/dev/null
ok "Keychain seeded ($KEYCHAIN_SERVICE/$KEYCHAIN_ACCOUNT)"

# --- Boot the runtime --------------------------------------------------------
BINARY="${BINARY:-.build/debug/andromeda-runtime}"
[[ -x "$BINARY" ]] || { echo "FAIL: $BINARY not built (run swift build first)"; exit 1; }

"$BINARY" serve \
  --host "$TAILNET_IP" \
  --port "$E2E_PORT" \
  --journal-path "$WORKDIR/journal.jsonl" \
  --mcp-bearer-token "$BROKER_TOKEN" \
  --github-token-service "$KEYCHAIN_SERVICE" \
  --github-token-account "$KEYCHAIN_ACCOUNT" \
  >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!

for _ in $(seq 1 30); do
  nc -z "$TAILNET_IP" "$E2E_PORT" 2>/dev/null && break
  sleep 0.5
done
nc -z "$TAILNET_IP" "$E2E_PORT" 2>/dev/null || { echo "FAIL: server did not boot"; tail -20 "$SERVER_LOG"; exit 1; }
ok "runtime up on $TAILNET_IP:$E2E_PORT (tailnet-only bind)"

MCP_URL="http://$TAILNET_IP:$E2E_PORT/mcp"
rpc() { # rpc <bearer> <json>
  curl -s -m 10 -X POST "$MCP_URL" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $1" \
    -d "$2"
}

# --- Host-side checks --------------------------------------------------------
UNAUTH="$(curl -s -o /dev/null -w '%{http_code}' -m 5 -X POST "$MCP_URL" -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}')"
check "no bearer → 401" "[[ '$UNAUTH' == '401' ]]"

LIST="$(rpc "$BROKER_TOKEN" '{"jsonrpc":"2.0","id":2,"method":"tools/list"}')"
check "tools/list exposes andromeda_github_get_me" "grep -q andromeda_github_get_me <<<\"\$LIST\""
check "tools/list does not leak the token" "! grep -q \"\$GH_TOKEN\" <<<\"\$LIST\""

CALL="$(rpc "$BROKER_TOKEN" '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"andromeda_github_get_me","arguments":{}}}')"
check "get_me round-trips (login: $GH_USER)" "grep -q \"\$GH_USER\" <<<\"\$CALL\""
check "get_me response redacts the token" "! grep -q \"\$GH_TOKEN\" <<<\"\$CALL\""

DENY="$(rpc "$BROKER_TOKEN" '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"andromeda_github_request","arguments":{"method":"PATCH","path":"/repos/Ripnrip/Andromeda","body":{}}}}')"
check "write denied without --automation-allowed" "grep -qi 'automation\\|denied\\|policy' <<<\"\$DENY\""
check "policy denial leaks no token" "! grep -q \"\$GH_TOKEN\" <<<\"\$DENY\""

# --- VM-side checks (the actual gate: keyless guest) --------------------------
VM_PROBE="$(ssh -o BatchMode=yes "$VM_SSH_HOST" 'env | grep -Ei "github|ghp_|xoxb" || true')"
check "VM env carries no GitHub/Slack credentials" "[[ -z \"\$VM_PROBE\" ]]"

VM_CALL="$(ssh -o BatchMode=yes "$VM_SSH_HOST" \
  "curl -s -m 15 -X POST 'http://$TAILNET_IP:$E2E_PORT/mcp' -H 'Content-Type: application/json' -H 'Authorization: Bearer $BROKER_TOKEN' -d '{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"andromeda_github_get_me\",\"arguments\":{}}}'")"
check "VM → /mcp get_me succeeds keyless (login: $GH_USER)" "grep -q \"\$GH_USER\" <<<\"\$VM_CALL\""
check "VM-visible response contains no token" "! grep -q \"\$GH_TOKEN\" <<<\"\$VM_CALL\""

VM_UNAUTH="$(ssh -o BatchMode=yes "$VM_SSH_HOST" \
  "curl -s -o /dev/null -w '%{http_code}' -m 10 -X POST 'http://$TAILNET_IP:$E2E_PORT/mcp' -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"tools/list\"}'")"
check "VM without bearer → 401" "[[ '$VM_UNAUTH' == '401' ]]"

VM_LOGS="$(ssh -o BatchMode=yes "$VM_SSH_HOST" "ls ~/.andromeda 2>/dev/null || true")"
check "VM wrote no local secret store" "[[ -z \"\$VM_LOGS\" ]]"

# --- Result ------------------------------------------------------------------
echo
echo "=== gate result: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
