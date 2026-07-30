// WhisperModel.swift
// LiveTranscribe
//
// Defines available faster-whisper model sizes with their metadata.

import Foundation

/// Available faster-whisper model sizes
enum WhisperModelSize: String, CaseIterable, Codable, Identifiable {
    case tiny    = "tiny"
    case base    = "base"
    case small   = "small"
    case medium  = "medium"
    case large   = "large-v3"

    var id: String { rawValue }

    /// Human-readable name with approximate disk size
    var displayName: String {
        switch self {
        case .tiny:   return "Tiny (~75 MB)"
        case .base:   return "Base (~140 MB)"
        case .small:  return "Small (~460 MB)"
        case .medium: return "Medium (~1.5 GB)"
        case .large:  return "Large v3 (~3 GB)"
        }
    }

    /// Short label used in the UI toolbar
    var shortName: String {
        switch self {
        case .tiny:   return "Tiny"
        case .base:   return "Base"
        case .small:  return "Small"
        case .medium: return "Medium"
        case .large:  return "Large"
        }
    }

    /// Qualitative accuracy description
    var accuracyDescription: String {
        switch self {
        case .tiny:   return "Fastest – lowest accuracy"
        case .base:   return "Fast – basic accuracy"
        case .small:  return "Balanced speed & accuracy"
        case .medium: return "High accuracy – moderate speed"
        case .large:  return "Best accuracy – slowest"
        }
    }

    /// Recommended for Apple Silicon
    var isRecommended: Bool { self == .base || self == .small }
}

/// Supported transcription languages
struct TranscriptionLanguage: Identifiable, Hashable {
    let id: String      // BCP-47 code, e.g. "en"
    let name: String    // Display name, e.g. "English"

    static let auto = TranscriptionLanguage(id: "auto", name: "Auto-detect")

    /// All languages faster-whisper supports
    static let all: [TranscriptionLanguage] = [
        .auto,
        TranscriptionLanguage(id: "en", name: "English"),
        TranscriptionLanguage(id: "zh", name: "Chinese"),
        TranscriptionLanguage(id: "de", name: "German"),
        TranscriptionLanguage(id: "es", name: "Spanish"),
        TranscriptionLanguage(id: "ru", name: "Russian"),
        TranscriptionLanguage(id: "ko", name: "Korean"),
        TranscriptionLanguage(id: "fr", name: "French"),
        TranscriptionLanguage(id: "ja", name: "Japanese"),
        TranscriptionLanguage(id: "pt", name: "Portuguese"),
        TranscriptionLanguage(id: "tr", name: "Turkish"),
        TranscriptionLanguage(id: "pl", name: "Polish"),
        TranscriptionLanguage(id: "it", name: "Italian"),
        TranscriptionLanguage(id: "sv", name: "Swedish"),
        TranscriptionLanguage(id: "nl", name: "Dutch"),
        TranscriptionLanguage(id: "hi", name: "Hindi"),
        TranscriptionLanguage(id: "ar", name: "Arabic"),
        TranscriptionLanguage(id: "fi", name: "Finnish"),
        TranscriptionLanguage(id: "id", name: "Indonesian"),
        TranscriptionLanguage(id: "uk", name: "Ukrainian"),
        TranscriptionLanguage(id: "cs", name: "Czech"),
        TranscriptionLanguage(id: "ro", name: "Romanian"),
        TranscriptionLanguage(id: "da", name: "Danish"),
        TranscriptionLanguage(id: "no", name: "Norwegian"),
        TranscriptionLanguage(id: "th", name: "Thai"),
        TranscriptionLanguage(id: "vi", name: "Vietnamese"),
        TranscriptionLanguage(id: "hu", name: "Hungarian"),
        TranscriptionLanguage(id: "sk", name: "Slovak"),
    ]
}
