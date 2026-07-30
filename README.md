# LiveTranscribe

> **Real-time transcript of any audio playing on your Mac — 100% local, zero cloud.**

LiveTranscribe captures system audio using ScreenCaptureKit and transcribes it live with [faster-whisper](https://github.com/SYSTRAN/faster-whisper) running entirely on your device. Watch YouTube, Udemy, Coursera, VLC, or any other audio source and get a searchable, exportable transcript in real time.

![Platform](https://img.shields.io/badge/macOS-13.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

---

## Features

| Category | Details |
|---|---|
| **Audio Capture** | ScreenCaptureKit system audio — no virtual device required |
| **Transcription** | faster-whisper (Tiny → Large v3), VAD filtering |
| **Live Display** | Always-on-top floating window, auto-scroll, timestamps |
| **Storage** | SQLite database, automatic session saving |
| **Export** | TXT · Markdown · SRT · WebVTT · PDF |
| **AI Features** | Summarise · Study Notes · Flashcards · Key Points · Action Items · Chat |
| **AI Backend** | Ollama (local LLM, fully offline) |
| **Interface** | Native SwiftUI, dark mode, menu bar icon |
| **Performance** | Optimised for Apple Silicon, non-blocking UI |

---

## Requirements

| Requirement | Minimum |
|---|---|
| macOS | **13.0 Ventura** |
| Xcode | **15.0** |
| Python | **3.8** |
| faster-whisper | latest |
| Ollama (optional) | latest (for AI features) |

---

## Quick Start

### 1 — Install Python dependencies

```bash
cd /path/to/LiveTranscribe
chmod +x scripts/install_deps.sh
./scripts/install_deps.sh
```

This installs `faster-whisper` and copies the bridge script to `~/Library/Application Support/LiveTranscribe/`.

### 2 — Open in Xcode

```bash
open LiveTranscribe.xcodeproj
```

### 3 — Sign the app

1. In Xcode, select the **LiveTranscribe** target.
2. Under **Signing & Capabilities**, choose your **Team**.
3. Xcode will auto-manage the bundle ID (`com.livetranscribe.app`).

### 4 — Build & Run

Press **⌘R** or **Product → Run**.

### 5 — Grant Screen Recording permission

On first launch, macOS will ask for **Screen Recording** permission (required for system audio capture). Click **Open System Preferences** and toggle LiveTranscribe on.

### 6 — Start transcribing

Press **⇧⌘R** or click the red ● button in the toolbar to start. The selected Whisper model will download automatically from HuggingFace on first use.

---

## Project Structure

```
LiveTranscribe/
├── LiveTranscribe.xcodeproj/        ← Xcode project (open this)
├── LiveTranscribe/
│   ├── App/
│   │   ├── LiveTranscribeApp.swift  ← @main entry point
│   │   └── AppDelegate.swift        ← Menu bar + floating window
│   ├── Models/
│   │   ├── TranscriptSession.swift  ← Session data model
│   │   ├── TranscriptSegment.swift  ← Segment data model
│   │   ├── WhisperModel.swift       ← Model size enum
│   │   └── AppSettings.swift        ← UserDefaults-backed settings
│   ├── ViewModels/
│   │   ├── TranscriptionViewModel.swift   ← Core orchestrator
│   │   ├── SessionHistoryViewModel.swift  ← History management
│   │   └── AIViewModel.swift             ← Ollama integration
│   ├── Services/
│   │   ├── AudioCaptureService.swift ← ScreenCaptureKit audio
│   │   ├── WhisperService.swift      ← Python subprocess bridge
│   │   ├── DatabaseService.swift     ← SQLite (libsqlite3)
│   │   ├── ExportService.swift       ← TXT/MD/SRT/VTT/PDF
│   │   └── AIService.swift           ← Ollama REST API
│   ├── Views/
│   │   ├── MainWindow/               ← ContentView, Sidebar, Detail
│   │   ├── FloatingWindow/           ← Always-on-top overlay
│   │   ├── Settings/                 ← Preferences pane
│   │   ├── AIPanel/                  ← AI features sheet
│   │   ├── Onboarding/               ← Setup guide
│   │   └── MenuBarView.swift         ← Status item popover
│   ├── Resources/
│   │   ├── Assets.xcassets/          ← App icon + accent colour
│   │   └── whisper_bridge.py         ← Python inference bridge
│   └── Supporting Files/
│       ├── Info.plist
│       └── LiveTranscribe.entitlements
└── scripts/
    └── install_deps.sh               ← Python dep installer
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         SwiftUI Views                       │
│   ContentView · SidebarView · FloatingTranscriptView etc.   │
└──────────────────────────┬──────────────────────────────────┘
                           │ @EnvironmentObject
┌──────────────────────────▼──────────────────────────────────┐
│                      ViewModels (@MainActor)                 │
│  TranscriptionVM · SessionHistoryVM · AIViewModel           │
└────────┬─────────────────┬──────────────────┬───────────────┘
         │                 │                  │
┌────────▼───────┐ ┌───────▼──────┐ ┌────────▼───────┐
│ AudioCapture   │ │  Whisper     │ │  DatabaseService│
│ Service        │ │  Service     │ │  (SQLite3 C API)│
│ (SCStream)     │ │  (Process)   │ └────────────────┘
└────────┬───────┘ └───────▲──────┘
    PCM  │                 │  JSON lines
   16kHz │   ┌─────────────┘
         └───►  whisper_bridge.py
              (faster-whisper VAD pipeline)
```

---

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| **⇧⌘R** | Start recording |
| **⌘.** | Stop recording |
| **⌘F** | Search transcript |
| **⇧⌘F** | Toggle floating window |
| **⌘,** | Open Settings |

---

## AI Features (Ollama)

Install Ollama and pull a model:

```bash
# Install Ollama
brew install ollama

# Start the server
ollama serve

# Pull a model (in another terminal)
ollama pull llama3        # ~4 GB, recommended
ollama pull mistral       # ~4 GB, alternative
ollama pull phi3:mini     # ~2 GB, fastest
```

AI features (summarise, notes, flashcards, chat) will be available once `ollama serve` is running.

---

## Whisper Models

| Model | Size | Speed | Accuracy | Best for |
|---|---|---|---|---|
| Tiny | ~75 MB | Fastest | Low | Quick drafts |
| Base | ~140 MB | Fast | Good | **Default** |
| Small | ~460 MB | Balanced | Better | Most use-cases |
| Medium | ~1.5 GB | Slow | High | Important content |
| Large v3 | ~3 GB | Slowest | Best | Maximum accuracy |

Models download automatically from HuggingFace on first use.

---

## Troubleshooting

### "Screen Recording permission denied"
Go to **System Preferences → Privacy & Security → Screen Recording** and enable LiveTranscribe.

### "Python 3 not found"
Install via Homebrew: `brew install python3`

### "faster-whisper not installed"
Run: `./scripts/install_deps.sh`  
Or manually: `pip3 install faster-whisper`

### Model loads but produces no output
- Ensure audio is actually playing (check macOS volume)
- Try the **Base** model first
- Enable VAD in Settings → Advanced

### AI features show "Ollama not detected"
Start Ollama: `ollama serve`  
Then click **Refresh** in the AI panel.

### Build error: "Missing team for code signing"
In Xcode → Target → Signing & Capabilities → choose your Apple ID team.

---

## Privacy

- **No audio leaves your Mac.** Ever.
- Transcription runs entirely on-device via faster-whisper.
- AI features use Ollama, which also runs locally.
- Sessions are stored in `~/Library/Application Support/LiveTranscribe/transcripts.sqlite`.
- No analytics, no tracking, no network requests (except Ollama on localhost).

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

## Acknowledgements

- [faster-whisper](https://github.com/SYSTRAN/faster-whisper) — CTranslate2-optimised Whisper
- [OpenAI Whisper](https://github.com/openai/whisper) — the underlying speech model
- [Ollama](https://ollama.ai) — local LLM inference
- [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit) — Apple system audio API
