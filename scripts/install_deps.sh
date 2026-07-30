#!/usr/bin/env bash
# install_deps.sh — LiveTranscribe
# Installs Python dependencies in a dedicated virtual environment for LiveTranscribe.

set -euo pipefail

CYAN='\033[0;36m'; GREEN='\033[0;32m'; RED='\033[0;31m'; RESET='\033[0m'

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${CYAN}  LiveTranscribe — Dependency Installer${RESET}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

# ── 1. Find System Python 3 ───────────────────────────────────────────────
SYSTEM_PY=""
for P in /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
    if command -v "$P" &>/dev/null; then
        SYSTEM_PY="$P"
        break
    fi
done

if [ -z "$SYSTEM_PY" ]; then
    echo -e "${RED}✗ Python 3 not found.${RESET}"
    echo "  Install via Homebrew:  brew install python3"
    exit 1
fi

PY_VER=$("$SYSTEM_PY" --version 2>&1)
echo -e "${GREEN}✓ Found base Python:${RESET} $PY_VER ($SYSTEM_PY)"

# ── 2. Create Virtual Environment ─────────────────────────────────────────
VENV_DIR="$HOME/Library/Application Support/LiveTranscribe/venv"
mkdir -p "$HOME/Library/Application Support/LiveTranscribe"

if [ ! -d "$VENV_DIR" ]; then
    echo "→ Creating virtual environment at: $VENV_DIR"
    "$SYSTEM_PY" -m venv "$VENV_DIR"
else
    echo -e "${GREEN}✓ Virtual environment exists at:${RESET} $VENV_DIR"
fi

VENV_PY="$VENV_DIR/bin/python3"

# ── 3. Install packages in venv ───────────────────────────────────────────
echo "→ Upgrading pip inside venv…"
"$VENV_PY" -m pip install --upgrade pip --quiet

echo "→ Installing faster-whisper and numpy…"
"$VENV_PY" -m pip install faster-whisper numpy --quiet

# ── 4. Verify ─────────────────────────────────────────────────────────────
echo ""
echo "→ Verifying installation…"
if "$VENV_PY" -c "from faster_whisper import WhisperModel; print('  faster-whisper OK')" 2>/dev/null; then
    echo -e "${GREEN}✓ All dependencies installed successfully in LiveTranscribe venv!${RESET}"
else
    echo -e "${RED}✗ faster-whisper import failed inside venv.${RESET}"
    exit 1
fi

# ── 5. Copy bridge script to App Support ──────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIDGE_SRC="$SCRIPT_DIR/../LiveTranscribe/Resources/whisper_bridge.py"
APP_SUPPORT="$HOME/Library/Application Support/LiveTranscribe"

if [ -f "$BRIDGE_SRC" ]; then
    cp "$BRIDGE_SRC" "$APP_SUPPORT/whisper_bridge.py"
    echo -e "${GREEN}✓ Bridge script copied to Application Support.${RESET}"
fi

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN}  Setup complete! LiveTranscribe is ready to transcribe audio.${RESET}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
