#!/usr/bin/env bash
# build_dmg.sh — LiveTranscribe
# Builds the app, assembles the .app bundle, signs it, and creates a DMG.
# Run from the project root: ./scripts/build_dmg.sh

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────
CYAN='\033[0;36m'; GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; RESET='\033[0m'

step() { echo -e "\n${CYAN}▶ $1${RESET}"; }
ok()   { echo -e "  ${GREEN}✓ $1${RESET}"; }
warn() { echo -e "  ${YELLOW}⚠ $1${RESET}"; }
die()  { echo -e "\n${RED}✗ $1${RESET}\n"; exit 1; }

echo -e "${CYAN}"
echo "  ██╗     ██╗██╗   ██╗███████╗"
echo "  ██║     ██║██║   ██║██╔════╝"
echo "  ██║     ██║██║   ██║█████╗  "
echo "  ██║     ██║╚██╗ ██╔╝██╔══╝  "
echo "  ███████╗██║ ╚████╔╝ ███████╗"
echo "  ╚══════╝╚═╝  ╚═══╝  ╚══════╝"
echo "  LiveTranscribe — DMG Builder"
echo -e "${RESET}"

# ── Paths ─────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="LiveTranscribe"
BUNDLE_ID="com.livetranscribe.app"
BUILD_DIR="$PROJECT_ROOT/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_DIR="$PROJECT_ROOT/dist"
DMG_PATH="$DMG_DIR/$APP_NAME.dmg"
BACKUP_DIR="$DMG_DIR/backups.noindex"
SDK=$(xcrun --show-sdk-path 2>/dev/null) || die "Xcode CLI tools not found. Run: xcode-select --install"

# ── Step 0: Pre-flight checks ─────────────────────────────────────────────
step "Pre-flight checks"

# Xcode license
if xcrun swiftc --version &>/dev/null; then
  ok "Xcode toolchain available"
else
  die "Xcode license not accepted. Run: sudo xcodebuild -license accept"
fi

# Python
PYTHON=""
VENV_PY="$HOME/Library/Application Support/LiveTranscribe/venv/bin/python3"
for P in "$VENV_PY" /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
  if [[ -x "$P" ]]; then PYTHON="$P"; break; fi
done
[[ -n "$PYTHON" ]] && ok "Python found: $PYTHON" || warn "Python not found (transcription will not work)"

# faster-whisper
if [[ -n "$PYTHON" ]] && "$PYTHON" -c "import faster_whisper" 2>/dev/null; then
  ok "faster-whisper installed"
else
  warn "faster-whisper not installed — run: pip3 install faster-whisper"
fi

# ── Step 1: Backup previous build & auto-increment version ────────────────
step "Archiving previous build & incrementing version"

mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Auto-increment version.json
if [[ -n "$PYTHON" ]]; then
  NEW_VER=$("$PYTHON" -c "
import json, os, datetime
vfile = '$DMG_DIR/version.json'
if os.path.exists(vfile):
    with open(vfile) as f: d = json.load(f)
    parts = d.get('version', '1.0.0').split('.')
    parts[-1] = str(int(parts[-1]) + 1)
    new_v = '.'.join(parts)
    d['version'] = new_v
    d['releaseDate'] = datetime.date.today().isoformat()
    d['downloadUrl'] = 'https://raw.githubusercontent.com/piyush215j/LiveTranscribe/main/dist/LiveTranscribe.dmg'
    with open(vfile, 'w') as f: json.dump(d, f, indent=2)
    print(new_v)
else:
    print('1.0.3')
")
  ok "Version incremented to: v$NEW_VER"
fi

if [[ -d "$APP_BUNDLE" ]]; then
  BACKUP_ZIP="$BACKUP_DIR/${APP_NAME}_v${NEW_VER}_${TIMESTAMP}.app.zip"
  (cd "$BUILD_DIR" && zip -r -q "$BACKUP_ZIP" "$APP_NAME.app")
  ok "Backup saved to: $BACKUP_ZIP"
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
ok "Clean build directory: $BUILD_DIR"

# ── Step 2: Compile Swift sources ─────────────────────────────────────────
step "Compiling Swift sources (this takes ~1-2 minutes)…"

SWIFT_SOURCES=(
  LiveTranscribe/Models/WhisperModel.swift
  LiveTranscribe/Models/TranscriptSession.swift
  LiveTranscribe/Models/TranscriptSegment.swift
  LiveTranscribe/Models/AppSettings.swift
  LiveTranscribe/Services/AIService.swift
  LiveTranscribe/Services/ExportService.swift
  LiveTranscribe/Services/WhisperService.swift
  LiveTranscribe/Services/DatabaseService.swift
  LiveTranscribe/Services/AudioCaptureService.swift
  LiveTranscribe/Services/UpdateService.swift
  LiveTranscribe/ViewModels/TranscriptionViewModel.swift
  LiveTranscribe/ViewModels/SessionHistoryViewModel.swift
  LiveTranscribe/ViewModels/AIViewModel.swift
  LiveTranscribe/App/AppDelegate.swift
  LiveTranscribe/App/LiveTranscribeApp.swift
  LiveTranscribe/Views/MainWindow/ContentView.swift
  LiveTranscribe/Views/MainWindow/SidebarView.swift
  LiveTranscribe/Views/MainWindow/TranscriptDetailView.swift
  LiveTranscribe/Views/FloatingWindow/FloatingTranscriptView.swift
  LiveTranscribe/Views/FloatingWindow/FloatingWindowController.swift
  LiveTranscribe/Views/Settings/SettingsView.swift
  LiveTranscribe/Views/Settings/UpdateView.swift
  LiveTranscribe/Views/AIPanel/AIPanelView.swift
  LiveTranscribe/Views/Onboarding/OnboardingView.swift
  LiveTranscribe/Views/MenuBarView.swift
)

cd "$PROJECT_ROOT"

xcrun swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macosx13.0 \
  -O \
  -module-name LiveTranscribe \
  -parse-as-library \
  -framework SwiftUI \
  -framework AppKit \
  -framework Foundation \
  -framework ScreenCaptureKit \
  -framework AVFoundation \
  -framework CoreMedia \
  -framework PDFKit \
  -lsqlite3 \
  -o "$BUILD_DIR/$APP_NAME" \
  "${SWIFT_SOURCES[@]}" \
  2>&1 | grep -v "^$" || true  # filter blank lines

[[ -f "$BUILD_DIR/$APP_NAME" ]] || die "Compilation failed. Check errors above."
ok "Binary compiled: $(du -sh "$BUILD_DIR/$APP_NAME" | cut -f1)"

# ── Step 3: Assemble .app bundle ──────────────────────────────────────────
step "Assembling .app bundle"

# Directory structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Binary
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Python bridge script
cp "$PROJECT_ROOT/LiveTranscribe/Resources/whisper_bridge.py" \
   "$APP_BUNDLE/Contents/Resources/whisper_bridge.py"

# AppIcon (.icns via built-in iconutil + actool if present)
ICNS_FILE="$PROJECT_ROOT/LiveTranscribe/Resources/AppIcon.icns"
ICONSET_SRC="$PROJECT_ROOT/LiveTranscribe/Resources/Assets.xcassets/AppIcon.appiconset"

if [[ -d "$ICONSET_SRC" ]]; then
  TMP_ICONSET="/tmp/AppIcon.iconset"
  rm -rf "$TMP_ICONSET"
  mkdir -p "$TMP_ICONSET"
  [[ -f "$ICONSET_SRC/icon_16x16.png" ]]   && cp "$ICONSET_SRC/icon_16x16.png" "$TMP_ICONSET/icon_16x16.png"
  [[ -f "$ICONSET_SRC/icon_32x32.png" ]]   && cp "$ICONSET_SRC/icon_32x32.png" "$TMP_ICONSET/icon_16x16@2x.png"
  [[ -f "$ICONSET_SRC/icon_32x32.png" ]]   && cp "$ICONSET_SRC/icon_32x32.png" "$TMP_ICONSET/icon_32x32.png"
  [[ -f "$ICONSET_SRC/icon_64x64.png" ]]   && cp "$ICONSET_SRC/icon_64x64.png" "$TMP_ICONSET/icon_32x32@2x.png"
  [[ -f "$ICONSET_SRC/icon_128x128.png" ]] && cp "$ICONSET_SRC/icon_128x128.png" "$TMP_ICONSET/icon_128x128.png"
  [[ -f "$ICONSET_SRC/icon_256x256.png" ]] && cp "$ICONSET_SRC/icon_256x256.png" "$TMP_ICONSET/icon_128x128@2x.png"
  [[ -f "$ICONSET_SRC/icon_256x256.png" ]] && cp "$ICONSET_SRC/icon_256x256.png" "$TMP_ICONSET/icon_256x256.png"
  [[ -f "$ICONSET_SRC/icon_512x512.png" ]] && cp "$ICONSET_SRC/icon_512x512.png" "$TMP_ICONSET/icon_256x256@2x.png"
  [[ -f "$ICONSET_SRC/icon_512x512.png" ]] && cp "$ICONSET_SRC/icon_512x512.png" "$TMP_ICONSET/icon_512x512.png"
  [[ -f "$ICONSET_SRC/icon_1024x1024.png" ]] && cp "$ICONSET_SRC/icon_1024x1024.png" "$TMP_ICONSET/icon_512x512@2x.png"

  iconutil -c icns "$TMP_ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns" 2>/dev/null || true
  cp "$APP_BUNDLE/Contents/Resources/AppIcon.icns" "$ICNS_FILE" 2>/dev/null || true
  rm -rf "$TMP_ICONSET"
  ok "Native AppIcon.icns generated & bundled"
elif [[ -f "$ICNS_FILE" ]]; then
  cp "$ICNS_FILE" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
  ok "AppIcon.icns copied to bundle"
fi

# Assets (compile xcassets → .car if actool is available)
if xcrun actool --version &>/dev/null; then
  xcrun actool \
    --output-format human-readable-text \
    --notices --warnings \
    --output-partial-info-plist /dev/null \
    --app-icon AppIcon \
    --accent-color AccentColor \
    --compress-pngs \
    --enable-on-demand-resources NO \
    --target-device mac \
    --minimum-deployment-target 13.0 \
    --platform macosx \
    --compile "$APP_BUNDLE/Contents/Resources" \
    "$PROJECT_ROOT/LiveTranscribe/Resources/Assets.xcassets" \
    2>/dev/null || true
fi

# Info.plist (generate a clean one)
cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>              <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>       <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>          <string>AppIcon</string>
  <key>CFBundleIconName</key>          <string>AppIcon</string>
  <key>CFBundleVersion</key>           <string>${NEW_VER:-1.0.3}</string>
  <key>CFBundleShortVersionString</key><string>${NEW_VER:-1.0.3}</string>
  <key>CFBundleExecutable</key>        <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>       <string>APPL</string>
  <key>LSMinimumSystemVersion</key>    <string>13.0</string>
  <key>LSApplicationCategoryType</key> <string>public.app-category.productivity</string>
  <key>NSPrincipalClass</key>          <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>   <true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>LiveTranscribe uses audio capture to transcribe audio playing on your Mac.</string>
</dict>
</plist>
PLIST

ok "Bundle assembled at: $APP_BUNDLE"

# ── Step 4: Code-sign ─────────────────────────────────────────────────────
step "Code-signing (ad-hoc with stable designated requirement)"

# Remove extended attributes (resource forks / AppleDouble files)
xattr -cr "$APP_BUNDLE"

# Create entitlements for the bundle
cat > "$BUILD_DIR/entitlements.plist" <<ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key><false/>
  <key>com.apple.security.cs.allow-jit</key><true/>
  <key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
</dict>
</plist>
ENT

codesign \
  --force \
  --deep \
  --sign "-" \
  --entitlements "$BUILD_DIR/entitlements.plist" \
  --options runtime \
  -r='designated => identifier "com.livetranscribe.app"' \
  "$APP_BUNDLE" 2>&1 \
  && ok "Ad-hoc code signature with stable designated requirement applied" \
  || warn "codesign failed — app may show Gatekeeper warning on first launch"

# Verify
codesign --verify --deep --strict "$APP_BUNDLE" 2>/dev/null \
  && ok "Signature verified" \
  || warn "Signature verification partial — this is expected for ad-hoc signing"

# ── Step 5: Create DMG ────────────────────────────────────────────────────
step "Creating DMG"

mkdir -p "$DMG_DIR"
rm -f "$DMG_PATH"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$APP_BUNDLE" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG_PATH" \
  > /dev/null

ok "DMG created: $DMG_PATH ($(du -sh "$DMG_PATH" | cut -f1))"

# ── Step 6: LaunchServices cleanup (prevent duplicate app icons) ───────────
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
  "$LSREGISTER" -u "$APP_BUNDLE" 2>/dev/null || true
  find "$PROJECT_ROOT" -name "*.app" -exec "$LSREGISTER" -u {} \; 2>/dev/null || true
  "$LSREGISTER" -r /Applications/LiveTranscribe.app 2>/dev/null || true
fi

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN}  ✅ Build complete!${RESET}"
echo ""
echo -e "  📦 DMG:  $DMG_PATH"
echo -e "  📁 App:  $APP_BUNDLE"
echo ""
echo -e "  To install:"
echo -e "  1. Double-click ${CYAN}$APP_NAME.dmg${RESET} in Finder"
echo -e "  2. Drag ${CYAN}$APP_NAME.app${RESET} → ${CYAN}Applications${RESET}"
echo -e "  3. Right-click the app → Open (first launch only, to bypass Gatekeeper)"
echo -e "  4. Run ${CYAN}./scripts/install_deps.sh${RESET} if not done already"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

# ── Optional: Open DMG in Finder ──────────────────────────────────────────
open "$DMG_DIR" 2>/dev/null || true
