// SidebarView.swift
// LiveTranscribe
//
// Left sidebar showing the list of past and live transcript sessions.

import SwiftUI

struct SidebarView: View {

    @EnvironmentObject var transcriptionVM: TranscriptionViewModel
    @EnvironmentObject var historyVM:       SessionHistoryViewModel
    @EnvironmentObject var settings:        AppSettings

    @State private var searchText         = ""
    @State private var showDeleteConfirm  = false
    @State private var sessionToDelete:   TranscriptSession?
    @State private var renameSession:     TranscriptSession?
    @State private var renameText         = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {

            // ── Search ────────────────────────────────────────────────────
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search sessions…", text: $historyVM.searchQuery)
                    .textFieldStyle(.plain)
                if !historyVM.searchQuery.isEmpty {
                    Button { historyVM.searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            Divider()

            // ── Live session ──────────────────────────────────────────────
            if let live = transcriptionVM.currentSession, transcriptionVM.isCapturing {
                LiveSessionRow(session: live, vm: transcriptionVM)
                    .onTapGesture { historyVM.selectedSession = live }
                Divider()
            }

            // ── History list ──────────────────────────────────────────────
            if historyVM.isLoading {
                ProgressView("Loading…")
                    .frame(maxHeight: .infinity)
            } else if historyVM.filteredSessions.isEmpty {
                EmptyHistoryView()
            } else {
                List(selection: $historyVM.selectedSession) {
                    ForEach(historyVM.filteredSessions) { session in
                        SessionRow(session: session)
                            .tag(session)
                            .contextMenu { contextMenu(for: session) }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .navigationTitle("Sessions")
        .toolbar {
            ToolbarItem {
                Button {
                    Task {
                        historyVM.selectedSession = nil
                        await transcriptionVM.startTranscription(resuming: nil)
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(transcriptionVM.isCapturing)
                .help("Start New Recording (⇧⌘N)")
            }

            ToolbarItem {
                Button {
                    Task { await historyVM.loadSessions() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh sessions")
            }
        }
        // Delete confirmation
        .alert("Delete Session?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let s = sessionToDelete { historyVM.deleteSession(s) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete \"\(sessionToDelete?.title ?? "")\" and all its segments.")
        }
        // Rename sheet
        .sheet(item: $renameSession) { s in
            renameSheet(for: s)
        }
        // Reload when a new session is finished
        .onChange(of: transcriptionVM.isCapturing) { capturing in
            if !capturing {
                Task { await historyVM.loadSessions() }
            }
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private func contextMenu(for session: TranscriptSession) -> some View {
        Button {
            historyVM.selectedSession = session
            Task {
                await transcriptionVM.startTranscription(resuming: session)
            }
        } label: {
            Label("Resume Recording", systemImage: "record.circle")
        }
        .disabled(transcriptionVM.isCapturing)

        Divider()

        Button("Rename…") {
            renameText   = session.title
            renameSession = session
        }

        Menu("Export…") {
            ForEach(ExportFormat.allCases) { fmt in
                Button(fmt.displayName) {
                    if let url = historyVM.export(session: session, format: fmt) {
                        NSWorkspace.shared.open(url.deletingLastPathComponent())
                    }
                }
            }
        }

        Divider()

        Button("Delete…", role: .destructive) {
            sessionToDelete  = session
            showDeleteConfirm = true
        }
    }

    // MARK: - Rename sheet

    private func renameSheet(for session: TranscriptSession) -> some View {
        VStack(spacing: 20) {
            Text("Rename Session")
                .font(.headline)
            TextField("Title", text: $renameText)
                .textFieldStyle(.roundedBorder)
                .focused($renameFocused)
                .onAppear { renameFocused = true }
            HStack {
                Button("Cancel") { renameSession = nil }
                Spacer()
                Button("Save") {
                    let t = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { historyVM.renameSession(session, to: t) }
                    renameSession = nil
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}

// MARK: - Session Row

private struct SessionRow: View {
    let session: TranscriptSession

    var body: some View {
        HStack(spacing: 10) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(session.formattedDate)
                    Text("·")
                    Text(session.formattedDuration)
                    Text("·")
                    Text(session.languageLabel.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.2))
                        .clipShape(Capsule())
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Live Session Row

private struct LiveSessionRow: View {
    let session: TranscriptSession
    @ObservedObject var vm: TranscriptionViewModel

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.2))
                    .frame(width: 36, height: 36)
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .scaleEffect(vm.isPaused ? 0.8 : 1.2)
                    .animation(.easeInOut(duration: 0.6).repeatForever(), value: vm.isPaused)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("● LIVE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.red)
                Text(session.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text("\(vm.liveSegments.count) segments")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.05))
    }
}

// MARK: - Empty state

private struct EmptyHistoryView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No Sessions Yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Press ⇧⌘R to start a new recording.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
