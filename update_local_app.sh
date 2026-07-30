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
mkdir -p /Applications
cp -R "$SCRIPT_DIR/build/LiveTranscribe.app" "/Applications/LiveTranscribe.app"
xattr -cr "/Applications/LiveTranscribe.app"

echo ""
echo -e "${GREEN}✓ /Applications/LiveTranscribe.app updated successfully!${RESET}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
