// ExportService.swift
// LiveTranscribe
//
// Exports transcript sessions to TXT, Markdown, SRT, WebVTT, and PDF.

import Foundation
import PDFKit
import AppKit

// MARK: - Export format

enum ExportFormat: String, CaseIterable, Identifiable {
    case txt      = "txt"
    case markdown = "md"
    case srt      = "srt"
    case vtt      = "vtt"
    case pdf      = "pdf"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .txt:      return "Plain Text (.txt)"
        case .markdown: return "Markdown (.md)"
        case .srt:      return "SubRip (.srt)"
        case .vtt:      return "WebVTT (.vtt)"
        case .pdf:      return "PDF (.pdf)"
        }
    }

    var fileExtension: String { rawValue }
}

// MARK: - ExportService

final class ExportService {

    static let shared = ExportService()
    private init() {}

    // MARK: - Public API

    /// Generates the file content for a given format and returns the file URL written to disk.
    func export(
        session: TranscriptSession,
        format: ExportFormat,
        to directory: URL
    ) throws -> URL {
        let filename = sanitiseFilename(session.title) + ".\(format.fileExtension)"
        let url = directory.appendingPathComponent(filename)

        switch format {
        case .txt:      try generateTXT(session: session, to: url)
        case .markdown: try generateMarkdown(session: session, to: url)
        case .srt:      try generateSRT(session: session, to: url)
        case .vtt:      try generateVTT(session: session, to: url)
        case .pdf:      try generatePDF(session: session, to: url)
        }

        return url
    }

    // MARK: - Generators

    private func generateTXT(session: TranscriptSession, to url: URL) throws {
        var lines: [String] = []
        lines.append("=== \(session.title) ===")
        lines.append("Date: \(session.startedAt.formatted(.dateTime))")
        lines.append("Model: \(session.modelUsed)  Language: \(session.languageLabel)")
        lines.append("Duration: \(session.formattedDuration)")
        lines.append(String(repeating: "─", count: 60))
        lines.append("")

        for seg in session.segments {
            lines.append("\(seg.formattedStartTime) \(seg.text)")
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func generateMarkdown(session: TranscriptSession, to url: URL) throws {
        var lines: [String] = []
        lines.append("# \(session.title)")
        lines.append("")
        lines.append("| Field | Value |")
        lines.append("|-------|-------|")
        lines.append("| **Date** | \(session.startedAt.formatted(.dateTime)) |")
        lines.append("| **Model** | \(session.modelUsed) |")
        lines.append("| **Language** | \(session.languageLabel) |")
        lines.append("| **Duration** | \(session.formattedDuration) |")
        lines.append("| **Words** | ~\(session.wordCount) |")
        lines.append("")
        lines.append("---")
        lines.append("")
        lines.append("## Transcript")
        lines.append("")

        for seg in session.segments {
            lines.append("**\(seg.formattedStartTime)** \(seg.text)")
            lines.append("")
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func generateSRT(session: TranscriptSession, to url: URL) throws {
        var lines: [String] = []
        for (index, seg) in session.segments.enumerated() {
            lines.append("\(index + 1)")
            lines.append("\(seg.srtStartTime) --> \(seg.srtEndTime)")
            lines.append(seg.text)
            lines.append("")
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func generateVTT(session: TranscriptSession, to url: URL) throws {
        var lines: [String] = ["WEBVTT", ""]
        lines.append("NOTE \(session.title)")
        lines.append("")

        for (index, seg) in session.segments.enumerated() {
            lines.append("cue-\(index + 1)")
            lines.append("\(seg.vttStartTime) --> \(seg.vttEndTime)")
            lines.append(seg.text)
            lines.append("")
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func generatePDF(session: TranscriptSession, to url: URL) throws {
        let pageSize = CGRect(x: 0, y: 0, width: 612, height: 792)  // US Letter
        let margin: CGFloat = 60

        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: nil, nil)
        else { throw ExportError.pdfCreationFailed }

        let mediaBox = pageSize
        ctx.beginPDFPage([kCGPDFContextMediaBox as String: NSValue(rect: mediaBox)] as CFDictionary)

        // Header
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 18),
            .foregroundColor: NSColor.black,
        ]
        let metaAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.gray,
        ]
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.black,
        ]
        let tsAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.systemBlue,
        ]

        // Draw title
        let titleStr = NSAttributedString(string: session.title, attributes: titleAttrs)
        var yPos = pageSize.height - margin

        func drawString(_ attrStr: NSAttributedString, at y: inout CGFloat) -> CGFloat {
            let textRect = CGRect(x: margin, y: y - 24, width: pageSize.width - margin * 2, height: 24)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            attrStr.draw(in: textRect)
            NSGraphicsContext.restoreGraphicsState()
            y -= 28
            return y
        }

        _ = drawString(titleStr, at: &yPos)

        let meta = "\(session.startedAt.formatted(.dateTime))  •  Model: \(session.modelUsed)  •  \(session.formattedDuration)"
        _ = drawString(NSAttributedString(string: meta, attributes: metaAttrs), at: &yPos)
        yPos -= 8

        // Draw a divider
        ctx.setStrokeColor(NSColor.gray.cgColor)
        ctx.move(to: CGPoint(x: margin, y: yPos))
        ctx.addLine(to: CGPoint(x: pageSize.width - margin, y: yPos))
        ctx.strokePath()
        yPos -= 16

        // Segments
        for seg in session.segments {
            if yPos < margin + 40 {
                // New page
                ctx.endPDFPage()
                ctx.beginPDFPage(nil)
                yPos = pageSize.height - margin
            }
            let tsStr   = NSAttributedString(string: seg.formattedStartTime + "  ", attributes: tsAttrs)
            let bodyStr = NSAttributedString(string: seg.text, attributes: bodyAttrs)
            let combined = NSMutableAttributedString()
            combined.append(tsStr)
            combined.append(bodyStr)

            let textRect = CGRect(
                x: margin, y: yPos - 40,
                width: pageSize.width - margin * 2, height: 40)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            combined.draw(in: textRect)
            NSGraphicsContext.restoreGraphicsState()
            yPos -= 20
        }

        ctx.endPDFPage()
        ctx.closePDF()

        try (pdfData as Data).write(to: url)
    }

    // MARK: - Helpers

    private func sanitiseFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
            .prefix(100)
            .description
    }
}

// MARK: - ExportError
enum ExportError: LocalizedError {
    case pdfCreationFailed
    var errorDescription: String? { "Failed to create PDF context." }
}
