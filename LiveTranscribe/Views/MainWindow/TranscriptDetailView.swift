// TranscriptDetailView.swift
// LiveTranscribe
//
// Shows the transcript for the currently selected or live session.
// Supports auto-scroll, search highlighting, speech card styling,
// on-hover segment copy, live audio waveform, and quick exports.

import SwiftUI
import AppKit

struct TranscriptDetailView: View {

    @EnvironmentObject var transcriptionVM: TranscriptionViewModel
    @EnvironmentObject var historyVM:       SessionHistoryViewModel
    @EnvironmentObject var settings:        AppSettings

    @State private var searchText     = ""
    @State private var showExportMenu = false
    @State private var exportResult:  URL?
    @State private var copiedSessionText = false

    // Determine what to display: live session OR selected history session
    private var displaySession: TranscriptSession? {
        if transcriptionVM.isCapturing {
            return transcriptionVM.currentSession
        }
        return historyVM.selectedSession
    }

    private var displaySegments: [TranscriptSegment] {
        if transcriptionVM.isCapturing {
            return transcriptionVM.filteredSegments
        }
        guard let session = historyVM.selectedSession else { return [] }
        let segs = session.segments
        guard !searchText.isEmpty else { return segs }
        return segs.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ZStack {
            if let session = displaySession {
                VStack(spacing: 0) {
                    // ── Header Bar ─────────────────────────────────────────
                    headerBar(session: session)
                    Divider()

                    // ── Transcript Scroll View ─────────────────────────────
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(displaySegments.enumerated()), id: \.element.id) { idx, seg in
                                    SegmentRow(
                                        segment: seg,
                                        isLatest: transcriptionVM.isCapturing && idx == displaySegments.count - 1,
                                        searchQuery: searchText,
                                        showTimestamp: settings.showTimestamps,
                                        fontSize: settings.fontSize
                                    )
                                    .id(seg.id)
                                }

                                // Bottom anchor for auto-scroll
                                Color.clear.frame(height: 8).id("bottom")
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                        }
                        .onChange(of: displaySegments.count) { _ in
                            if settings.autoScroll && transcriptionVM.isCapturing {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    proxy.scrollTo("bottom")
                                }
                            }
                        }
                    }

                    Divider()
                    // ── Bottom Bar ─────────────────────────────────────────
                    bottomBar(session: session)
                }
            } else {
                placeholderView
            }

            // ── Model Loading Overlay ──────────────────────────────────────
            if transcriptionVM.isModelLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    VStack(spacing: 6) {
                        Text("Initializing \(settings.whisperModel.shortName) Model…")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Preparing audio engine  •  \(transcriptionVM.formattedLoadingTime)")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(24)
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                .shadow(radius: 10)
                .transition(.opacity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .searchable(text: $searchText, prompt: "Search transcript…")
        .onChange(of: searchText) { q in
            transcriptionVM.searchQuery = q
        }
    }

    // MARK: - Header

    private func headerBar(session: TranscriptSession) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(session.title)
                        .font(.system(size: 15, weight: .semibold))

                    if transcriptionVM.isCapturing {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                            Text("RECORDING")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(.red)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }

                HStack(spacing: 10) {
                    Label(session.formattedDuration, systemImage: "clock")
                    Label(session.modelUsed, systemImage: "cpu")
                    Label(session.languageLabel, systemImage: "globe")
                    Label("\(displaySegments.count) segments", systemImage: "text.bubble")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Live Audio Waveform Visualizer
            if transcriptionVM.isCapturing {
                LiveWaveformVisualizer(level: transcriptionVM.audioLevel, isPaused: transcriptionVM.isPaused)
                    .frame(width: 80, height: 24)
                    .padding(.trailing, 4)

                // Pause / Resume Button
                Button {
                    transcriptionVM.togglePause()
                } label: {
                    Label(
                        transcriptionVM.isPaused ? "Resume" : "Pause",
                        systemImage: transcriptionVM.isPaused
                            ? "play.circle.fill" : "pause.circle.fill"
                    )
                }
                .buttonStyle(.bordered)
                .tint(transcriptionVM.isPaused ? .green : .orange)
            } else {
                // Resume recording button
                Button {
                    Task {
                        await transcriptionVM.startTranscription(resuming: session)
                    }
                } label: {
                    Label("Resume Recording", systemImage: "record.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .help("Resume recording and transcribing into this session")
            }

            // Export menu
            Menu {
                ForEach(ExportFormat.allCases) { fmt in
                    Button(fmt.displayName) {
                        exportSession(session, format: fmt)
                    }
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Bottom bar

    private func bottomBar(session: TranscriptSession) -> some View {
        HStack(spacing: 14) {
            Text("~\(session.wordCount) words")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            // Copy all transcript text button
            Button {
                let full = session.fullText
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(full, forType: .string)
                copiedSessionText = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    copiedSessionText = false
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: copiedSessionText ? "checkmark" : "doc.on.doc")
                    Text(copiedSessionText ? "Copied All" : "Copy All")
                }
                .font(.system(size: 11))
                .foregroundStyle(copiedSessionText ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            if let url = exportResult {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Exported")
                    Button("Show in Finder") {
                        NSWorkspace.shared.open(url.deletingLastPathComponent())
                        exportResult = nil
                    }
                    .font(.caption)
                }
                .font(.caption)
                .transition(.opacity)
            }

            Toggle("Timestamps", isOn: $settings.showTimestamps)
                .toggleStyle(.checkbox)
                .font(.caption)

            Toggle("Auto-scroll", isOn: $settings.autoScroll)
                .toggleStyle(.checkbox)
                .font(.caption)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Placeholder View

    private var placeholderView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 90, height: 90)
                Image(systemName: "waveform")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 6) {
                Text("LiveTranscribe")
                    .font(.system(size: 26, weight: .bold))
                Text("AI-powered system audio transcription running 100% on-device.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    shortcutBadge(keys: "⇧⌘N", action: "Start New Recording")
                    shortcutBadge(keys: "⌥⌘R", action: "Resume Selected Session")
                    shortcutBadge(keys: "⌘.", action: "Stop Recording")
                }
            }

            HStack(spacing: 12) {
                featureChip(icon: "cpu", text: "faster-whisper AI")
                featureChip(icon: "lock.shield", text: "100% Offline")
                featureChip(icon: "apple.intelligence", text: "Apple Silicon Optimized")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func shortcutBadge(keys: String, action: String) -> some View {
        HStack(spacing: 6) {
            Text(keys)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(action)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func featureChip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.1))
        .clipShape(Capsule())
        .foregroundStyle(Color.accentColor)
    }

    // MARK: - Export

    private func exportSession(_ session: TranscriptSession, format: ExportFormat) {
        Task {
            if transcriptionVM.isCapturing {
                exportResult = await transcriptionVM.export(format: format)
            } else {
                exportResult = historyVM.export(session: session, format: format)
            }
        }
    }
}

// MARK: - Segment Row (Speech Card)

private struct SegmentRow: View {
    let segment:       TranscriptSegment
    let isLatest:      Bool
    let searchQuery:   String
    let showTimestamp:  Bool
    let fontSize:      Double

    @State private var isHovering = false
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if showTimestamp {
                Text(segment.formattedStartTime)
                    .font(.system(size: max(10, fontSize - 3), weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .frame(width: 76, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 4) {
                highlightedText
                    .font(.system(size: fontSize))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Quick Copy on hover
            if isHovering {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(segment.text, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(copied ? Color.green : Color.secondary)
                        .padding(4)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Copy segment text")
                .transition(.opacity)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isLatest
                      ? Color.accentColor.opacity(0.08)
                      : (isHovering ? Color.secondary.opacity(0.08) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isLatest ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var highlightedText: some View {
        if searchQuery.isEmpty {
            Text(segment.text)
                .foregroundStyle(.primary)
        } else {
            let text = segment.text
            let ranges = text.ranges(of: searchQuery, options: .caseInsensitive)
            if ranges.isEmpty {
                Text(text).opacity(0.4)
            } else {
                buildHighlightedText(text: text, ranges: ranges)
            }
        }
    }

    private func buildHighlightedText(
        text: String, ranges: [Range<String.Index>]
    ) -> some View {
        var result = AttributedString(text)
        for range in ranges {
            if let attrRange = Range(range, in: result) {
                result[attrRange].backgroundColor = .yellow
                result[attrRange].foregroundColor = .black
            }
        }
        return Text(result)
    }
}

// MARK: - Live Waveform Visualizer

private struct LiveWaveformVisualizer: View {
    let level: Float
    let isPaused: Bool

    private let barCount = 10

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(
                        LinearGradient(
                            colors: isPaused ? [.orange.opacity(0.6), .orange] : [.green, .cyan],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 3, height: barHeight(for: index))
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        if isPaused { return 4 }
        let factor = sin(Double(index) / Double(barCount) * .pi)
        let normalizedLevel = CGFloat(min(max(level * 3.0, 0.1), 1.0))
        let height = 4 + (20 * normalizedLevel * CGFloat(factor))
        return max(4, min(height, 22))
    }
}

// MARK: - String ranges helper

extension String {
    func ranges(of searchString: String, options: CompareOptions = []) -> [Range<Index>] {
        var result: [Range<Index>] = []
        var start = startIndex
        while start < endIndex,
              let range = range(of: searchString, options: options, range: start..<endIndex) {
            result.append(range)
            start = range.upperBound
        }
        return result
    }
}
