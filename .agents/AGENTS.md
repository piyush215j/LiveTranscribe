# AI Agent Directive — LiveTranscribe Update & Versioning Rules

> **MANDATORY FOR ALL AI AGENTS:** Read and strictly follow these rules whenever modifying code, building, or updating LiveTranscribe.

---

## 1. Versioning & Single DMG Rule
- **No multiple DMG filenames:** Never create separate versioned DMG files (e.g. `LiveTranscribe-1.1.dmg`, `LiveTranscribe-1.2.dmg`).
- **Single DMG target:** Always output the primary DMG to:
  `dist/LiveTranscribe.dmg`
- **Auto-increment version.json:** Every time code or UI changes are made, automatically increment the patch version in `dist/version.json` (e.g. `1.0.2` → `1.0.3` → `1.0.4`).

---

## 2. Backup Archive Rule
- **Preserve Previous Builds:** Before building a new app bundle, copy the existing build to the backup directory:
  `dist/backups/LiveTranscribe_v{PREVIOUS_VERSION}_{TIMESTAMP}.app`
- **Never overwrite backups:** Ensure all past versions remain stored in `dist/backups/` so any previous build can be restored.

---

## 3. Seamless 1-Click Update Rule
- Whenever code changes are made, run `./scripts/build_dmg.sh` or `./update_local_app.sh`.
- The build script must:
  1. Backup previous build to `dist/backups/`
  2. Increment version in `dist/version.json`
  3. Recompile Swift sources into `build/LiveTranscribe.app`
  4. Create/update `dist/LiveTranscribe.dmg`
  5. Unregister intermediate build from LaunchServices (`lsregister -u`)
  6. Update `/Applications/LiveTranscribe.app`
- When the user clicks **Check for Updates…** inside the app, `UpdateService` reads `dist/version.json`, detects the higher version, and performs a 1-click update.

---

## 4. Verification Check
- Verify Swift compilation with `xcrun swiftc -parse` before replacing binaries.
- Ensure ScreenCaptureKit, CoreGraphics (`CGPreflightScreenCaptureAccess`), and Python bridge paths remain intact.
