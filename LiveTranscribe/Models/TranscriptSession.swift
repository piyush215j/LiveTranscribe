// TranscriptSession.swift
// LiveTranscribe
//
// Represents a single transcription recording session.

import Foundation

/// A recording session that contains one or more transcript segments.
struct TranscriptSession: Identifiable, Hashable, Codable {
    /// Database row ID
    var id: Int64
    /// User-facing title (auto-generated or renamed)
    var title: String
    /// When recording started
    var startedAt: Date
    /// When recording ended (nil if still active)
    var endedAt: Date?
    /// Whisper model used
    var modelUsed: String
    /// Language code or "auto"
    var language: String
    /// Segments loaded separately to avoid large fetches
    var segments: [TranscriptSegment]

    // MARK: - Computed helpers

    /// Total duration in seconds
    var duration: TimeInterval {
        if let maxSegmentEnd = segments.map(\.endTime).max(), maxSegmentEnd > 0 {
            return maxSegmentEnd
        }
        guard let end = endedAt else {
            return Date().timeIntervalSince(startedAt)
        }
        return end.timeIntervalSince(startedAt)
    }

    /// Duration formatted as HH:MM:SS
    var formattedDuration: String {
        let d = Int(duration)
        let h = d / 3600
        let m = (d % 3600) / 60
        let s = d % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }

    /// Combined transcript text for all segments
    var fullText: String {
        segments.map(\.text).joined(separator: "\n")
    }

    /// Word count estimate
    var wordCount: Int {
        fullText.split(separator: " ").count
    }

    /// Display language label
    var languageLabel: String {
        if language == "auto" { return "Auto" }
        return TranscriptionLanguage.all.first { $0.id == language }?.name ?? language.uppercased()
    }

    /// Date formatted for display in sidebar
    var formattedDate: String {
        let formatter = DateFormatter()
        let cal = Calendar.current
        if cal.isDateInToday(startedAt) {
            formatter.dateFormat = "h:mm a"
        } else if cal.isDateInYesterday(startedAt) {
            return "Yesterday"
        } else {
            formatter.dateStyle = .medium
        }
        return formatter.string(from: startedAt)
    }

    // MARK: - Empty initialiser

    static func empty() -> TranscriptSession {
        TranscriptSession(
            id: 0,
            title: "New Session",
            startedAt: Date(),
            endedAt: nil,
            modelUsed: WhisperModelSize.base.rawValue,
            language: "auto",
            segments: []
        )
    }
}
