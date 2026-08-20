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
NEW_ICON="$SCRIPT_DIR/build/LiveTranscribe.app/Contents/Resources/AppIcon.icns"
NEW_PLIST="$SCRIPT_DIR/build/LiveTranscribe.app/Contents/Info.plist"

# ── Surgical update: preserve the existing bundle so macOS TCC permissions
# (Screen Recording) survive across updates. Only replace binary and resources,
# and sign with the stable designated requirement (identifier "com.livetranscribe.app").
if [[ -d "$INSTALLED_APP" ]]; then
  # 1. Replace compiled binary
  cp "$NEW_BINARY" "$INSTALLED_APP/Contents/MacOS/LiveTranscribe"
  chmod +x "$INSTALLED_APP/Contents/MacOS/LiveTranscribe"

  # 2. Replace Python bridge script & AppIcon & Info.plist
  [[ -f "$NEW_BRIDGE" ]] && cp "$NEW_BRIDGE" "$INSTALLED_APP/Contents/Resources/whisper_bridge.py"
  [[ -f "$NEW_ICON" ]]   && cp "$NEW_ICON" "$INSTALLED_APP/Contents/Resources/AppIcon.icns"
  [[ -f "$NEW_PLIST" ]]  && cp "$NEW_PLIST" "$INSTALLED_APP/Contents/Info.plist"

  # 3. Re-sign the existing bundle in-place with stable designated requirement
  xattr -cr "$INSTALLED_APP"
  codesign --force --deep --sign "-" \
    --entitlements "$SCRIPT_DIR/build/entitlements.plist" \
    --options runtime \
    -r='designated => identifier "com.livetranscribe.app"' \
    "$INSTALLED_APP" 2>/dev/null || true
else
  # First-time install — copy the whole bundle
  mkdir -p /Applications
  cp -R "$SCRIPT_DIR/build/LiveTranscribe.app" "$INSTALLED_APP"
  xattr -cr "$INSTALLED_APP"
fi

# Refresh Finder / Dock icon cache
touch "$INSTALLED_APP"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
  "$LSREGISTER" -f "$INSTALLED_APP" 2>/dev/null || true
fi

echo ""
echo -e "${GREEN}✓ /Applications/LiveTranscribe.app updated successfully!${RESET}"
echo -e "  (Binary replaced in-place — Screen Recording permission preserved)"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
