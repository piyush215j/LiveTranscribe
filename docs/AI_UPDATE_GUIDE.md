# LiveTranscribe — Architecture & AI Developer Guide

[![macOS 13.0+](https://img.shields.io/badge/macOS-13.0%2B-blue.svg)](https://apple.com/macos)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![faster-whisper](https://img.shields.io/badge/faster--whisper-local-green.svg)](https://github.com/SYSTRAN/faster-whisper)

**LiveTranscribe** is a native macOS application that captures system audio in real-time (videos, YouTube, Udemy, Zoom, VLC) and generates offline live transcripts using `faster-whisper`.

---

## 🛠️ Architecture Map

```
               ┌────────────────────────┐
               │    ScreenCaptureKit    │
               └───────────┬────────────┘
                           │ 16kHz PCM Float32
                           ▼
               ┌────────────────────────┐
               │  AudioCaptureService   │
               └───────────┬────────────┘
                           │ Int16 PCM Chunk (stdin)
                           ▼
               ┌────────────────────────┐
               │   whisper_bridge.py    │ (Python Subprocess)
               └───────────┬────────────┘
                           │ JSON Segment Stream (stdout)
                           ▼
               ┌────────────────────────┐
               │     WhisperService     │
               └───────────┬────────────┘
                           │ @MainActor Task
                           ▼
               ┌────────────────────────┐
               │ TranscriptionViewModel │ ──► Floating Window & Detail View
               └────────────────────────┘
```

---

## 🔒 Critical Subsystems (DO NOT ALTER)

1. **Permission Check (`AudioCaptureService.swift`):**
   - CoreGraphics `CGPreflightScreenCaptureAccess()` and `CGRequestScreenCaptureAccess()` MUST be called before `SCShareableContent.current`.
2. **Audio Buffer Extraction (`AudioCaptureService.swift`):**
   - Uses `CMBlockBufferCopyDataBytes` directly to prevent buffer list alignment failures on multi-channel YouTube streams.
3. **Subprocess Deadlock Prevention (`WhisperService.swift`):**
   - `attachStderrReader` continuously drains `stderr` to prevent OS pipe buffer deadlocks during HuggingFace download logging.
4. **App Icon Plist Key (`Info.plist`):**
   - `<key>CFBundleIconFile</key><string>AppIcon</string>` must remain in `Info.plist`.
5. **No-Index Backup Storage (`scripts/build_dmg.sh`):**
   - Backups are stored as `.app.zip` inside `dist/backups.noindex/` to prevent duplicate Launchpad icons.

---

## 🚀 How to Execute Updates (AI Assistant Workflow)

Whenever you edit code to add a feature or fix a bug:

```bash
# 1. Run local build & updater pipeline
./update_local_app.sh

# 2. Push changes to GitHub repository
git add .
git commit -m "Update feature description"
git push origin main
```

- `./update_local_app.sh` automatically increments `dist/version.json`, packages `dist/LiveTranscribe.dmg`, and updates `/Applications/LiveTranscribe.app`.
- The user can click **Check for Updates…** inside the app to fetch the update directly from GitHub!
