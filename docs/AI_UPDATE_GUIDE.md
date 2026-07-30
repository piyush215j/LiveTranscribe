# AI Developer Update & Build Specifications

> This document defines the automated update pipeline, single DMG output, version incrementing, and backup retention rules for LiveTranscribe.

## Workflow Overview

```
Code Edit ──► Auto-Increment version.json ──► Backup previous .app in dist/backups/ ──► Compile & Code-Sign ──► Update dist/LiveTranscribe.dmg ──► Update /Applications/LiveTranscribe.app
```

---

## 1. Single DMG Output Policy

All builds generate a single, clean DMG:
- **Location:** `dist/LiveTranscribe.dmg`
- No version numbers in the DMG filename.

---

## 2. Automatic Backup Archiving

Before compiling a new version, the existing app bundle is automatically copied to `dist/backups/`:
- **Format:** `dist/backups/LiveTranscribe_v{version}_{YYYYMMDD_HHMMSS}.app`
- This ensures full version history is preserved locally.

---

## 3. Auto-Incrementing Versioning

The build script `scripts/build_dmg.sh` automatically reads `dist/version.json`, increments the patch version (e.g. `1.0.3` → `1.0.4`), and updates `releaseDate`.

```json
{
  "version": "1.0.3",
  "releaseDate": "2026-07-30",
  "releaseNotes": "• Latest features & improvements.",
  "downloadUrl": "/Users/piyush/Desktop/temp/LiveTranscribe/dist/LiveTranscribe.dmg",
  "minOSVersion": "13.0"
}
```

---

## 4. In-App Update Flow

When the user clicks **Check for Updates…** inside the app:
1. `UpdateService` queries `dist/version.json`.
2. Detects the higher version.
3. Shows release notes and **Install & Relaunch**.
4. Installs the new `.app` into `/Applications/LiveTranscribe.app` and relaunches seamlessly.
