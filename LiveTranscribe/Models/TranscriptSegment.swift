// TranscriptSegment.swift
// LiveTranscribe
//
// A single transcribed chunk of speech with timing information.

import Foundation

/// One timed piece of transcription, produced by Whisper.
struct TranscriptSegment: Identifiable, Hashable, Codable {
    /// Database row ID (0 = unsaved)
    var id: Int64
    /// Parent session ID
    var sessionId: Int64
    /// Transcribed text
    var text: String
    /// Seconds from session start
    var startTime: Double
    /// Seconds from session start (end of speech)
    var endTime: Double
    /// Detected language code, e.g. "en"
    var language: String
    /// Wall-clock timestamp when segment was created
    var createdAt: Date

    // MARK: - Formatted timestamps

    /// Start time formatted as [HH:MM:SS] or [MM:SS]
    var formattedStartTime: String {
        formatSeconds(startTime)
    }

    /// End time formatted
    var formattedEndTime: String {
        formatSeconds(endTime)
    }

    /// Duration of this segment in seconds
    var duration: Double { endTime - startTime }

    // MARK: - SRT / VTT helpers

    /// SRT timestamp e.g. 00:01:23,456
    var srtStartTime: String { srtTimestamp(startTime) }
    var srtEndTime:   String { srtTimestamp(endTime) }

    /// WebVTT timestamp e.g. 00:01:23.456
    var vttStartTime: String { vttTimestamp(startTime) }
    var vttEndTime:   String { vttTimestamp(endTime) }

    // MARK: - Private formatters

    private func formatSeconds(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "[%d:%02d:%02d]", h, m, s)
        } else {
            return String(format: "[%02d:%02d]", m, s)
        }
    }

    private func srtTimestamp(_ seconds: Double) -> String {
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }

    private func vttTimestamp(_ seconds: Double) -> String {
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d.%03d", h, m, s, ms)
    }
}
