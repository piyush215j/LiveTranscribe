// TranscriptionViewModel.swift
// LiveTranscribe
//
// Core orchestrator: coordinates audio capture, Whisper transcription,
// live segment display, and database persistence.

import Foundation
import Combine
import SwiftUI

@MainActor
final class TranscriptionViewModel: ObservableObject {

    // MARK: - Published state

    @Published private(set) var isCapturing   = false
    @Published private(set) var isPaused      = false
    @Published private(set) var isModelLoading = false
    @Published private(set) var loadingTimerSeconds = 0
    @Published private(set) var statusMessage = "Ready"
    @Published private(set) var audioLevel:  Float = 0.0

    @Published var currentSession:  TranscriptSession?
    @Published var liveSegments:    [TranscriptSegment] = []
    @Published var searchQuery      = ""

    @Published var errorMessage:    String?
    @Published var showFloatingWindow = false
    @Published var showOnboarding   = false

    // MARK: - Services

    let audioCapture = AudioCaptureService()
    private let whisper   = WhisperService()
    private let db        = DatabaseService.shared
    let settings    = AppSettings.shared

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private var sessionStartTime: Date?
    private var timerCancellable: AnyCancellable?

    // MARK: - Init

    init() {
        bindServices()
    }

    // MARK: - Bindings

    private func bindServices() {
        // Pass audio chunks from capture → whisper (skip if paused)
        audioCapture.audioDataPublisher
            .filter { [weak self] _ in !(self?.isPaused ?? true) }
            .sink { [weak self] data in
                self?.whisper.sendAudioData(data)
            }
            .store(in: &cancellables)

        // New segments from whisper → UI + database
        whisper.segmentPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] seg in
                self?.handleNewSegment(seg)
            }
            .store(in: &cancellables)

        // Mirror audio level
        audioCapture.$audioLevel
            .receive(on: DispatchQueue.main)
            .assign(to: &$audioLevel)

        // Mirror model-loading state with timer
        whisper.$isModelLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                guard let self = self else { return }
                self.isModelLoading = isLoading
                if isLoading {
                    self.startLoadingTimer()
                } else {
                    self.stopLoadingTimer()
                }
            }
            .store(in: &cancellables)

        // Mirror status message
        whisper.$statusMessage
            .receive(on: DispatchQueue.main)
            .assign(to: &$statusMessage)

        // Propagate whisper errors
        whisper.errorPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] msg in
                self?.errorMessage = msg
            }
            .store(in: &cancellables)
    }

    // MARK: - Transcription control

    func startTranscription() async {
        guard !isCapturing else { return }

        // Check audio permission first
        let hasPermission = await audioCapture.checkPermission()
        guard hasPermission else {
            errorMessage = audioCapture.errorMessage ?? "Permission denied."
            showOnboarding = true
            return
        }

        do {
            // Create a new database session
            let dateStr = Date().formatted(.dateTime.month(.abbreviated).day().hour().minute())
            let session = try db.createSession(
                title: "Session – \(dateStr)",
                modelUsed: settings.whisperModel.rawValue,
                language: settings.language
            )
            currentSession   = session
            liveSegments     = []
            sessionStartTime = Date()
            errorMessage     = nil

            // Start Whisper bridge
            try whisper.start(
                model: settings.whisperModel,
                language: settings.language
            )

            // Start audio capture
            try await audioCapture.startCapture()

            isCapturing = true
            isPaused    = false
            statusMessage = "Waiting for model…"

        } catch {
            errorMessage  = error.localizedDescription
            isCapturing   = false
            statusMessage = "Error"
        }
    }

    func stopTranscription() async {
        guard isCapturing else { return }

        await audioCapture.stopCapture()
        whisper.stop()

        // Persist session end time
        if let session = currentSession {
            try? db.updateSessionEnd(id: session.id, endedAt: Date())
            var updated  = session
            updated.endedAt  = Date()
            updated.segments = liveSegments
            currentSession   = updated
        }

        isCapturing   = false
        isPaused      = false
        statusMessage = "Recording saved"
    }

    func togglePause() {
        guard isCapturing else { return }
        isPaused = !isPaused
        statusMessage = isPaused ? "Paused" : "Transcribing…"
    }

    // MARK: - Session management

    func renameCurrentSession(_ newTitle: String) {
        guard let session = currentSession else { return }
        try? db.updateSessionTitle(newTitle, id: session.id)
        currentSession?.title = newTitle
    }

    // MARK: - Segment handling

    private func handleNewSegment(_ whisperSeg: WhisperSegment) {
        guard let session = currentSession else { return }

        var seg = TranscriptSegment(
            id: 0,
            sessionId: session.id,
            text: whisperSeg.text,
            startTime: whisperSeg.start,
            endTime: whisperSeg.end,
            language: whisperSeg.language,
            createdAt: Date()
        )

        // Try to persist; use the unsaved version as fallback
        if settings.autoSave,
           let saved = try? db.insertSegment(seg) {
            seg = saved
        }

        liveSegments.append(seg)
    }

    // MARK: - Search

    var filteredSegments: [TranscriptSegment] {
        guard !searchQuery.isEmpty else { return liveSegments }
        return liveSegments.filter {
            $0.text.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    // MARK: - Export

    func export(format: ExportFormat) async -> URL? {
        guard var session = currentSession else { return nil }
        session.segments = liveSegments

        let exportDir = URL(fileURLWithPath: settings.exportFolderPath)
        return try? ExportService.shared.export(
            session: session, format: format, to: exportDir)
    }

    // MARK: - Floating window

    func toggleFloatingWindow() {
        showFloatingWindow.toggle()
    }

    // MARK: - Recent segments for floating window

    var recentSegments: [TranscriptSegment] {
        let count = settings.floatingWindowLineCount
        return Array(liveSegments.suffix(count))
    }

    // MARK: - Loading Timer Helpers

    private func startLoadingTimer() {
        loadingTimerSeconds = 0
        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.loadingTimerSeconds += 1
            }
    }

    private func stopLoadingTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
        loadingTimerSeconds = 0
    }

    var formattedLoadingTime: String {
        let m = loadingTimerSeconds / 60
        let s = loadingTimerSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}
