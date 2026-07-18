#!/usr/bin/env bash
# Build AndromedaHome and/or AndromedaHUD → ~/Applications/*.app → adhoc codesign → launch
# Why: linker-signed SPM binaries inside a .app trip taskgated
# ("code has no resources but signature indicates they must be present").
# Always strip + resign after copy. See multibrain PROOFS/38-codesign-adhoc-apps-2026-07-17.md
#
# Usage:
#   ./scripts/install-and-sign.sh              # AndromedaHome (default)
#   ./scripts/install-and-sign.sh home         # AndromedaHome
#   ./scripts/install-and-sign.sh hud          # AndromedaHUD + LaunchAgent com.andromeda.hud
#   ./scripts/install-and-sign.sh both         # Home + HUD (+ HUD LaunchAgent)
#
# HUD LaunchAgent: ops/com.andromeda.hud.plist → ~/Library/LaunchAgents/ (RunAtLoad, no KeepAlive)
# HUD must NOT be started with `open -a` from agent shells (inherits OPENROUTER_*/paid keys).
# Prefer: launchctl kickstart -k gui/$(id -u)/com.andromeda.hud
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-home}"
VERSION="${CFBundleShortVersionString:-0.3}"
BUILD="$(date +%Y%m%d%H%M)"

install_product() {
  local PRODUCT="$1"
  local BUNDLE_ID="$2"
  local DISPLAY_NAME="$3"
  local LSUI_ELEMENT="$4"
  # launch_mode: "open" (Home) | "none" (HUD — LaunchAgent kickstart after install)
  local LAUNCH_MODE="${5:-open}"
  local APP="${HOME}/Applications/${PRODUCT}.app"

  echo "==> Building ${PRODUCT}"
  cd "$ROOT"
  swift build -c release --product "$PRODUCT"
  local BIN="$ROOT/.build/release/$PRODUCT"
  test -x "$BIN"

  pkill -x "$PRODUCT" 2>/dev/null || true
  sleep 0.3

  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cp "$BIN" "$APP/Contents/MacOS/$PRODUCT"
  chmod +x "$APP/Contents/MacOS/$PRODUCT"

  cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDisplayName</key>
	<string>${DISPLAY_NAME}</string>
	<key>CFBundleExecutable</key>
	<string>${PRODUCT}</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleName</key>
	<string>${DISPLAY_NAME}</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${BUILD}</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<${LSUI_ELEMENT}/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
PLIST

  codesign --remove-signature "$APP/Contents/MacOS/$PRODUCT" 2>/dev/null || true
  codesign --remove-signature "$APP" 2>/dev/null || true
  codesign --force --deep --sign - "$APP"
  codesign --verify --deep --strict "$APP"

  case "$LAUNCH_MODE" in
    open)
      open -a "$APP"
      echo "Installed + signed + opened: $APP"
      ;;
    none)
      echo "Installed + signed (no open): $APP"
      ;;
    *)
      echo "Unknown launch_mode: $LAUNCH_MODE" >&2
      exit 1
      ;;
  esac
}

# Install RunAtLoad LaunchAgent (no KeepAlive). Plist must point at ~/Applications/*.app.
# Then kickstart so HUD starts under launchd (clean env), never via agent-shell `open -a`.
install_launch_agent() {
  local LABEL="$1"
  local PLIST_SRC="$2"
  local DEST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
  local UID_NUM
  UID_NUM="$(id -u)"

  test -f "$PLIST_SRC"
  mkdir -p "${HOME}/.multibrain/logs" "${HOME}/Library/LaunchAgents"
  cp "$PLIST_SRC" "$DEST"

  # Prefer modern bootstrap; fall back to load if already registered under legacy path.
  launchctl bootout "gui/${UID_NUM}/${LABEL}" 2>/dev/null || true
  if launchctl bootstrap "gui/${UID_NUM}" "$DEST" 2>/dev/null; then
    echo "LaunchAgent bootstrapped: gui/${UID_NUM}/${LABEL}"
  else
    launchctl unload "$DEST" 2>/dev/null || true
    launchctl load "$DEST"
    echo "LaunchAgent loaded (legacy): $DEST"
  fi
  # Force a clean start under launchd even if RunAtLoad already fired.
  launchctl kickstart -k "gui/${UID_NUM}/${LABEL}" 2>/dev/null \
    || launchctl kickstart "gui/${UID_NUM}/${LABEL}" 2>/dev/null \
    || true
  echo "LaunchAgent kickstarted: gui/${UID_NUM}/${LABEL}"
  launchctl print "gui/${UID_NUM}/${LABEL}" 2>/dev/null | head -20 || true
}

case "$TARGET" in
  home|Home|AndromedaHome)
    install_product "AndromedaHome" "com.andromeda.home" "Andromeda Home" "false" "open"
    ;;
  hud|HUD|AndromedaHUD)
    # Accessory HUD — local-only (no OpenRouter / paid env vars). Launch via LaunchAgent only.
    install_product "AndromedaHUD" "com.andromeda.hud" "Andromeda HUD" "true" "none"
    install_launch_agent "com.andromeda.hud" "$ROOT/ops/com.andromeda.hud.plist"
    ;;
  both|all)
    install_product "AndromedaHome" "com.andromeda.home" "Andromeda Home" "false" "open"
    install_product "AndromedaHUD" "com.andromeda.hud" "Andromeda HUD" "true" "none"
    install_launch_agent "com.andromeda.hud" "$ROOT/ops/com.andromeda.hud.plist"
    ;;
  *)
    echo "Usage: $0 [home|hud|both]" >&2
    exit 1
    ;;
esac
