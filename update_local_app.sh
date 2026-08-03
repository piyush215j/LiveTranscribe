#!/usr/bin/env bash
# update_local_app.sh — LiveTranscribe
# Rebuilds the app binary and updates /Applications/LiveTranscribe.app in 1 step.

set -euo pipefail

CYAN='\033[0;36m'; GREEN='\033[0;32m'; RED='\033[0;31m'; RESET='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${CYAN}  LiveTranscribe — Local App Update${RESET}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

echo "→ Building app bundle and DMG..."
./scripts/build_dmg.sh

echo ""
echo "→ Updating /Applications/LiveTranscribe.app..."

INSTALLED_APP="/Applications/LiveTranscribe.app"
NEW_BINARY="$SCRIPT_DIR/build/LiveTranscribe.app/Contents/MacOS/LiveTranscribe"
NEW_BRIDGE="$SCRIPT_DIR/build/LiveTranscribe.app/Contents/Resources/whisper_bridge.py"

# ── Surgical update: preserve the existing bundle so macOS TCC permissions
# (Screen Recording) survive across updates. Only replace the binary and
# resource files — never the bundle itself.
if [[ -d "$INSTALLED_APP" ]]; then
  # 1. Replace only the compiled binary
  cp "$NEW_BINARY" "$INSTALLED_APP/Contents/MacOS/LiveTranscribe"
  chmod +x "$INSTALLED_APP/Contents/MacOS/LiveTranscribe"

  # 2. Replace Python bridge script
  [[ -f "$NEW_BRIDGE" ]] && cp "$NEW_BRIDGE" "$INSTALLED_APP/Contents/Resources/whisper_bridge.py"

  # 3. Re-sign the existing bundle in-place (same container, same path)
  xattr -cr "$INSTALLED_APP"
  codesign --force --deep --sign "-" \
    --entitlements "$SCRIPT_DIR/build/entitlements.plist" \
    --options runtime \
    "$INSTALLED_APP" 2>/dev/null || true
else
  # First-time install — copy the whole bundle
  mkdir -p /Applications
  cp -R "$SCRIPT_DIR/build/LiveTranscribe.app" "$INSTALLED_APP"
  xattr -cr "$INSTALLED_APP"
fi

echo ""
echo -e "${GREEN}✓ /Applications/LiveTranscribe.app updated successfully!${RESET}"
echo -e "  (Binary replaced in-place — Screen Recording permission preserved)"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
