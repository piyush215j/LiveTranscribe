// TranscriptDetailView.swift
// LiveTranscribe
//
// Shows the transcript for the currently selected or live session.
// Supports auto-scroll, search highlighting, pause/resume, and export.

import SwiftUI

struct TranscriptDetailView: View {

    @EnvironmentObject var transcriptionVM: TranscriptionViewModel
    @EnvironmentObject var historyVM:       SessionHistoryViewModel
    @EnvironmentObject var settings:        AppSettings

    @State private var searchText     = ""
    @State private var showExportMenu = false
    @State private var exportResult:  URL?

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
                    // Header bar
                    headerBar(session: session)
                    Divider()

                    // Transcript scroll view
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(displaySegments) { seg in
                                    SegmentRow(
                                        segment: seg,
                                        searchQuery: searchText,
                                        showTimestamp: settings.showTimestamps,
                                        fontSize: settings.fontSize
                                    )
                                    .id(seg.id)
                                }

                                // Bottom anchor for auto-scroll
                                Color.clear.frame(height: 1).id("bottom")
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
                    bottomBar(session: session)
                }
            } else {
                placeholderView
            }

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
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(size: 15, weight: .semibold))
                HStack(spacing: 8) {
                    Label(session.formattedDuration, systemImage: "clock")
                    Label(session.modelUsed, systemImage: "cpu")
                    Label(session.languageLabel, systemImage: "globe")
                    Label("\(displaySegments.count) segments", systemImage: "text.bubble")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            Spacer()

            if transcriptionVM.isCapturing {
                // Pause / Resume
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
                // Resume recording into this existing session
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
        HStack {
            Text("~\(session.wordCount) words")
                .font(.caption)
                .foregroundStyle(.tertiary)

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

    // MARK: - Placeholder

    private var placeholderView: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform")
                .font(.system(size: 60))
                .foregroundStyle(.quinary)

            Text("LiveTranscribe")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.primary)

            Text("Press ⇧⌘R to begin capturing system audio\nor select a past session from the sidebar.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                featureChip(icon: "cpu", text: "Local AI")
                featureChip(icon: "lock.shield", text: "100% Offline")
                featureChip(icon: "apple.intelligence", text: "Apple Silicon")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func featureChip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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

// MARK: - Segment Row

private struct SegmentRow: View {
    let segment:      TranscriptSegment
    let searchQuery:  String
    let showTimestamp: Bool
    let fontSize:     Double

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if showTimestamp {
                Text(segment.formattedStartTime)
                    .font(.system(size: fontSize - 2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .leading)
                    .padding(.top, 1)
            }

            highlightedText
                .font(.system(size: fontSize))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.clear)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var highlightedText: some View {
        if searchQuery.isEmpty {
            Text(segment.text)
        } else {
            // Highlight matching text
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
