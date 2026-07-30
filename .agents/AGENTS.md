# LiveTranscribe — AI Agent Directives & Architecture Specs

> **MANDATORY FOR ALL AI AGENTS & ASSISTANTS:**
> Read this file completely BEFORE making any code edits, adding features, or running updates.

---

## 1. Project Overview & Tech Stack
- **Name:** LiveTranscribe
- **Platform:** Native macOS Desktop Application (macOS 13.0+)
- **GitHub Repository:** `https://github.com/piyush215j/LiveTranscribe`
- **Languages/Frameworks:** Swift 5, SwiftUI, ScreenCaptureKit, CoreGraphics, AVFoundation, PDFKit, SQLite3, Python 3 (`faster-whisper`).

---

## 2. Core Systems — DO NOT BREAK

### A. Screen Capture & Audio Permissions (`AudioCaptureService.swift`)
- MUST use `CGPreflightScreenCaptureAccess()` and `CGRequestScreenCaptureAccess()` before `SCShareableContent.current`.
- Extract audio bytes via `CMBlockBufferCopyDataBytes` directly from `CMSampleBuffer`. DO NOT use `AudioBufferList` stride calculation (breaks multi-channel YouTube audio).

### B. Speech Recognition Subprocess (`WhisperService.swift` & `whisper_bridge.py`)
- Python bridge runs via subprocess using stdin (Int16 16kHz PCM) and stdout (JSON segment stream).
- MUST attach a continuous `stderr` stream reader (`attachStderrReader`) in `WhisperService.swift` to prevent process deadlock when `tqdm` or HuggingFace outputs download logs.
- `findPython()` prioritizes `/opt/homebrew/bin/python3` and `~/Library/Application Support/LiveTranscribe/venv/bin/python3`.

### C. App Icon & Metadata (`Info.plist`)
- MUST maintain `<key>CFBundleIconFile</key><string>AppIcon</string>` in `Info.plist` template.
- Master icon script is at `scripts/process_user_logo.py` (processes 1500x1500 centered white squircle).

---

## 3. Automated Update & Build Pipeline

When the user asks to modify code or push a new feature update:

1. **Implement Requested Features:** Make necessary Swift / Python changes.
2. **Execute Local Build Pipeline:**
   Run `./update_local_app.sh` in project root.
   This automatically:
   - Auto-increments patch version in `dist/version.json`
   - Archives previous build into `.zip` inside `dist/backups.noindex/`
   - Compiles Swift sources and compiles `AppIcon` assets
   - Ad-hoc code-signs bundle (`xattr -cr`)
   - Generates single unified installer `dist/LiveTranscribe.dmg`
   - Unregisters build directory from LaunchServices (`lsregister -u`)
   - Updates `/Applications/LiveTranscribe.app` cleanly
3. **Push to GitHub:**
   Run:
   ```bash
   git add .
   git commit -m "Feature update description"
   git push origin main
   ```
4. **Instruct User on Release Tagging:**
   Tell the user to draft a GitHub Release with tag `vX.Y.Z` on `github.com/piyush215j/LiveTranscribe/releases` and upload `dist/LiveTranscribe.dmg`.
5. **In-App Update Verification:**
   User clicks **LiveTranscribe → Check for Updates…** inside the app to apply the update in 1 click!

---

## 4. Single-DMG & No-Duplicate Rules
- NEVER create separate versioned DMG files (e.g. `LiveTranscribe-1.1.dmg`). Always output to `dist/LiveTranscribe.dmg`.
- ALL backup builds MUST be zipped into `dist/backups.noindex/` so macOS Launchpad and Spotlight never display duplicate app icons.
