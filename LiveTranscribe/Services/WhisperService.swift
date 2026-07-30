// WhisperService.swift
// LiveTranscribe
//
// Manages the faster-whisper Python subprocess bridge.
// Sends 16 kHz mono PCM audio via stdin; receives JSON segment lines on stdout.

import Foundation
import Combine

// MARK: - Domain types

/// A transcribed speech segment returned by the Whisper bridge
struct WhisperSegment {
    let text:     String
    let start:    Double   // seconds from session start
    let end:      Double
    let language: String
}

/// Errors raised by WhisperService
enum WhisperError: LocalizedError {
    case pythonNotFound
    case bridgeScriptNotFound
    case modelLoadFailed(String)
    case processNotRunning

    var errorDescription: String? {
        switch self {
        case .pythonNotFound:
            return "Python 3 not found. Install it with:\n  brew install python3"
        case .bridgeScriptNotFound:
            return "Whisper bridge script (whisper_bridge.py) not found in app bundle."
        case .modelLoadFailed(let msg):
            return "Model failed to load: \(msg)"
        case .processNotRunning:
            return "The Whisper transcription process is not running."
        }
    }
}

// MARK: - WhisperService

/// Manages the Python faster-whisper subprocess.
@MainActor
final class WhisperService: ObservableObject {

    // MARK: Published state

    @Published private(set) var isRunning      = false
    @Published private(set) var isModelLoading = false
    @Published private(set) var statusMessage  = "Not started"
    @Published private(set) var detectedLanguage: String = ""

    /// Emits new transcript segments as they arrive
    let segmentPublisher = PassthroughSubject<WhisperSegment, Never>()
    /// Emits error descriptions
    let errorPublisher   = PassthroughSubject<String, Never>()

    // MARK: Private

    private var process:    Process?
    private var stdinPipe:  Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    private let outputQueue = DispatchQueue(
        label: "com.livetranscribe.whisper.output",
        qos: .userInteractive
    )
    private let bufferLock  = NSLock()
    nonisolated(unsafe) private var outputBuffer = Data()

    // MARK: - Python environment detection

    /// Searches common macOS locations for a python3 executable.
    private nonisolated func findPython() -> String? {
        let appSupportVenv = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LiveTranscribe/venv/bin/python3").path

        var candidates = [
            "/opt/homebrew/bin/python3",      // Homebrew Apple Silicon
            "/opt/homebrew/bin/python3.14",
            "/opt/homebrew/bin/python3.13",
            "/opt/homebrew/bin/python3.12",
            "/opt/homebrew/bin/python3.11",
            "/usr/local/bin/python3",         // Homebrew Intel
            "/usr/bin/python3",               // Xcode CLI tools
        ]

        if let venv = appSupportVenv, FileManager.default.isExecutableFile(atPath: venv) {
            candidates.insert(venv, at: 0)
        }
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        // Last resort: ask the shell
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-c", "which python3 2>/dev/null"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = Pipe()
        try? p.run()
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (out?.isEmpty == false) ? out : nil
    }

    /// Locates the bundled whisper_bridge.py script.
    private nonisolated func findBridgeScript() -> String? {
        // 1. App bundle (normal distribution)
        if let p = Bundle.main.path(forResource: "whisper_bridge", ofType: "py") {
            return p
        }
        // 2. App Support (useful during development)
        if let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let p = base
                .appendingPathComponent("LiveTranscribe")
                .appendingPathComponent("whisper_bridge.py")
            if FileManager.default.fileExists(atPath: p.path) { return p.path }
        }
        // 3. Next to the binary (Xcode run)
        if let execURL = Bundle.main.executableURL {
            let p = execURL
                .deletingLastPathComponent()
                .appendingPathComponent("whisper_bridge.py")
            if FileManager.default.fileExists(atPath: p.path) { return p.path }
        }
        return nil
    }

    // MARK: - Start / Stop

    func start(model: WhisperModelSize, language: String) throws {
        guard !isRunning else { return }

        guard let pythonPath = findPython() else {
            throw WhisperError.pythonNotFound
        }
        guard let scriptPath = findBridgeScript() else {
            throw WhisperError.bridgeScriptNotFound
        }

        isModelLoading = true
        statusMessage  = "Loading \(model.shortName) model…"

        let p      = Process()
        let stdin  = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        p.executableURL = URL(fileURLWithPath: pythonPath)

        var args = [scriptPath, "--model", model.rawValue]
        if language != "auto" && !language.isEmpty {
            args += ["--language", language]
        }
        p.arguments = args

        p.standardInput  = stdin
        p.standardOutput = stdout
        p.standardError  = stderr

        // Propagate the caller's PATH so that python can locate its packages
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONIOENCODING"] = "utf-8"
        p.environment = env

        // React when the process exits unexpectedly
        p.terminationHandler = { [weak self] proc in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isRunning {
                    self.isRunning      = false
                    self.isModelLoading = false
                    self.statusMessage  = "Process exited (\(proc.terminationStatus))"
                }
            }
        }

        try p.run()

        self.process   = p
        self.stdinPipe  = stdin
        self.stdoutPipe = stdout
        self.stderrPipe = stderr
        self.isRunning  = true

        attachStdoutReader(to: stdout)
        attachStderrReader(to: stderr)
    }

    private func attachStderrReader(to pipe: Pipe) {
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { fh in
            let data = fh.availableData
            if let str = String(data: data, encoding: .utf8), !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("[Whisper python stderr]: \(str)")
            }
        }
    }

    func stop() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        try? stdinPipe?.fileHandleForWriting.close()
        process?.terminate()
        process    = nil
        stdinPipe  = nil
        stdoutPipe = nil
        stderrPipe = nil
        isRunning      = false
        isModelLoading = false
        statusMessage  = "Stopped"
        outputBuffer   = Data()
    }

    // MARK: - Audio input

    /// Write a chunk of 16 kHz mono Int16 PCM to the bridge's stdin.
    func sendAudioData(_ data: Data) {
        guard isRunning, !isModelLoading,
              let handle = stdinPipe?.fileHandleForWriting else { return }
        do {
            try handle.write(contentsOf: data)
        } catch {
            // Pipe closed — process probably died
        }
    }

    // MARK: - Stdout reader

    private func attachStdoutReader(to pipe: Pipe) {
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            guard !data.isEmpty else {
                fh.readabilityHandler = nil
                return
            }
            self?.outputQueue.async {
                self?.appendOutputDataLocked(data)
            }
        }
    }

    private nonisolated func appendOutputDataLocked(_ data: Data) {
        bufferLock.lock()
        outputBuffer.append(data)

        // Process every complete newline-terminated JSON line
        var linesToProcess: [String] = []
        while let nlRange = outputBuffer.firstRange(of: Data([0x0A])) {
            let lineData = outputBuffer[outputBuffer.startIndex..<nlRange.lowerBound]
            outputBuffer.removeSubrange(outputBuffer.startIndex...nlRange.lowerBound)
            if let line = String(data: lineData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
               !line.isEmpty {
                linesToProcess.append(line)
            }
        }
        bufferLock.unlock()

        for line in linesToProcess {
            Task { @MainActor [weak self] in
                self?.processLine(line)
            }
        }
    }

    @MainActor
    private func processLine(_ line: String) {
        guard let jsonData = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else { return }

        // Status messages from bridge startup
        if let status = json["status"] as? String {
            switch status {
            case "loading":
                isModelLoading = true
                statusMessage  = "Loading model…"
            case "ready":
                isModelLoading = false
                statusMessage  = "Transcribing…"
            default: break
            }
            return
        }

        // Error from bridge
        if let errMsg = json["error"] as? String {
            isModelLoading = false
            statusMessage  = "Error: \(errMsg)"
            errorPublisher.send(errMsg)
            return
        }

        // Transcript segment
        if let type = json["type"] as? String, type == "segment",
           let text  = json["text"]  as? String, !text.isEmpty,
           let start = json["start"] as? Double,
           let end   = json["end"]   as? Double {

            let lang = json["language"] as? String ?? "unknown"
            detectedLanguage = lang

            let seg = WhisperSegment(
                text: text, start: start, end: end, language: lang)
            segmentPublisher.send(seg)
        }
    }
}
