// AppSettings.swift
// LiveTranscribe
//
// Observable singleton for all user-configurable settings.
// Changes are immediately persisted to UserDefaults.

import Foundation
import Combine

/// Convenience extension to get `nil` when a Double was never stored
private extension Double {
    var storedNonZero: Double? { self == 0.0 ? nil : self }
}

/// App-wide settings object, injected into the environment.
final class AppSettings: ObservableObject {

    // MARK: - Singleton
    static let shared = AppSettings()

    // MARK: - Published properties

    /// Which faster-whisper model to use for transcription
    @Published var whisperModel: WhisperModelSize {
        didSet { save(Keys.whisperModel, value: whisperModel.rawValue) }
    }

    /// BCP-47 language code or "auto"
    @Published var language: String {
        didSet { save(Keys.language, value: language) }
    }

    /// Transcript display font size (points)
    @Published var fontSize: Double {
        didSet { save(Keys.fontSize, value: fontSize) }
    }

    /// Show timestamps alongside each segment
    @Published var showTimestamps: Bool {
        didSet { save(Keys.showTimestamps, value: showTimestamps) }
    }

    /// Auto-save sessions to SQLite
    @Published var autoSave: Bool {
        didSet { save(Keys.autoSave, value: autoSave) }
    }

    /// Auto-scroll to the newest segment
    @Published var autoScroll: Bool {
        didSet { save(Keys.autoScroll, value: autoScroll) }
    }

    /// Path to folder where transcripts are stored
    @Published var transcriptFolderPath: String {
        didSet { save(Keys.transcriptFolder, value: transcriptFolderPath) }
    }

    /// Path to folder where exports are saved
    @Published var exportFolderPath: String {
        didSet { save(Keys.exportFolder, value: exportFolderPath) }
    }

    /// Floating window background opacity (0–1)
    @Published var floatingWindowOpacity: Double {
        didSet { save(Keys.floatingWindowOpacity, value: floatingWindowOpacity) }
    }

    /// Number of recent segments shown in floating window
    @Published var floatingWindowLineCount: Int {
        didSet { save(Keys.floatingWindowLineCount, value: floatingWindowLineCount) }
    }

    /// VAD (Voice Activity Detection) sensitivity in Python bridge
    @Published var vadEnabled: Bool {
        didSet { save(Keys.vadEnabled, value: vadEnabled) }
    }

    /// Seconds between Whisper inference chunks
    @Published var chunkDuration: Double {
        didSet { save(Keys.chunkDuration, value: chunkDuration) }
    }

    // MARK: - Private

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let whisperModel         = "whisperModel"
        static let language             = "language"
        static let fontSize             = "fontSize"
        static let showTimestamps       = "showTimestamps"
        static let autoSave             = "autoSave"
        static let autoScroll           = "autoScroll"
        static let transcriptFolder     = "transcriptFolder"
        static let exportFolder         = "exportFolder"
        static let floatingWindowOpacity    = "floatingWindowOpacity"
        static let floatingWindowLineCount  = "floatingWindowLineCount"
        static let vadEnabled           = "vadEnabled"
        static let chunkDuration        = "chunkDuration"
    }

    private init() {
        let modelRaw = defaults.string(forKey: Keys.whisperModel) ?? WhisperModelSize.base.rawValue
        whisperModel = WhisperModelSize(rawValue: modelRaw) ?? .base

        language     = defaults.string(forKey: Keys.language) ?? "auto"
        fontSize     = defaults.double(forKey: Keys.fontSize).storedNonZero ?? 15.0
        showTimestamps   = defaults.object(forKey: Keys.showTimestamps)  as? Bool ?? true
        autoSave         = defaults.object(forKey: Keys.autoSave)        as? Bool ?? true
        autoScroll       = defaults.object(forKey: Keys.autoScroll)      as? Bool ?? true

        let defaultDocs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?.path ?? NSHomeDirectory()

        transcriptFolderPath = defaults.string(forKey: Keys.transcriptFolder) ?? defaultDocs
        exportFolderPath     = defaults.string(forKey: Keys.exportFolder) ?? defaultDocs

        floatingWindowOpacity   = defaults.double(forKey: Keys.floatingWindowOpacity).storedNonZero ?? 0.90
        floatingWindowLineCount = defaults.integer(forKey: Keys.floatingWindowLineCount) == 0
                                  ? 5
                                  : defaults.integer(forKey: Keys.floatingWindowLineCount)
        vadEnabled     = defaults.object(forKey: Keys.vadEnabled) as? Bool ?? true
        chunkDuration  = defaults.double(forKey: Keys.chunkDuration).storedNonZero ?? 5.0
    }

    // MARK: - Helpers

    private func save(_ key: String, value: Any) {
        defaults.set(value, forKey: key)
    }

    /// Reset all settings to factory defaults
    func resetToDefaults() {
        whisperModel = .base
        language = "auto"
        fontSize = 15.0
        showTimestamps = true
        autoSave = true
        autoScroll = true
        let defaultDocs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?.path ?? NSHomeDirectory()
        transcriptFolderPath = defaultDocs
        exportFolderPath = defaultDocs
        floatingWindowOpacity = 0.90
        floatingWindowLineCount = 5
        vadEnabled = true
        chunkDuration = 5.0
    }
}
