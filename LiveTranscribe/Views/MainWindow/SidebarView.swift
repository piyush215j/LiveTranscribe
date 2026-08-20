// SidebarView.swift
// LiveTranscribe
//
// Left sidebar showing the list of past and live transcript sessions.
// Features date grouping, pinned sessions, search filtering, and quick actions.

import SwiftUI

struct SidebarView: View {

    @EnvironmentObject var transcriptionVM: TranscriptionViewModel
    @EnvironmentObject var historyVM:       SessionHistoryViewModel
    @EnvironmentObject var settings:        AppSettings

    @AppStorage("pinnedSessionIds") private var pinnedIdsRaw: String = ""
    @State private var showDeleteConfirm  = false
    @State private var sessionToDelete:   TranscriptSession?
    @State private var renameSession:     TranscriptSession?
    @State private var renameText         = ""
    @FocusState private var renameFocused: Bool

    // MARK: - Pinned IDs Helpers

    private var pinnedIds: Set<Int64> {
        Set(pinnedIdsRaw.split(separator: ",").compactMap { Int64($0) })
    }

    private func isPinned(_ session: TranscriptSession) -> Bool {
        pinnedIds.contains(session.id)
    }

    private func togglePin(_ session: TranscriptSession) {
        var current = pinnedIds
        if current.contains(session.id) {
            current.remove(session.id)
        } else {
            current.insert(session.id)
        }
        pinnedIdsRaw = current.map(String.init).joined(separator: ",")
    }

    // MARK: - Grouping Helpers

    private var allFiltered: [TranscriptSession] {
        historyVM.filteredSessions
    }

    private var pinnedSessions: [TranscriptSession] {
        allFiltered.filter { isPinned($0) }
    }

    private var unpinnedSessions: [TranscriptSession] {
        allFiltered.filter { !isPinned($0) }
    }

    private var todaySessions: [TranscriptSession] {
        let cal = Calendar.current
        return unpinnedSessions.filter { cal.isDateInToday($0.startedAt) }
    }

    private var yesterdaySessions: [TranscriptSession] {
        let cal = Calendar.current
        return unpinnedSessions.filter { cal.isDateInYesterday($0.startedAt) }
    }

    private var pastWeekSessions: [TranscriptSession] {
        let cal = Calendar.current
        let sevenDaysAgo = cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return unpinnedSessions.filter {
            !cal.isDateInToday($0.startedAt) &&
            !cal.isDateInYesterday($0.startedAt) &&
            $0.startedAt >= sevenDaysAgo
        }
    }

    private var olderSessions: [TranscriptSession] {
        let cal = Calendar.current
        let sevenDaysAgo = cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return unpinnedSessions.filter {
            !cal.isDateInToday($0.startedAt) &&
            !cal.isDateInYesterday($0.startedAt) &&
            $0.startedAt < sevenDaysAgo
        }
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Search Bar ─────────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                TextField("Search sessions or text…", text: $historyVM.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !historyVM.searchQuery.isEmpty {
                    Button { historyVM.searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(8)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            // ── Live session banner ────────────────────────────────────────
            if let live = transcriptionVM.currentSession, transcriptionVM.isCapturing {
                LiveSessionRow(session: live, vm: transcriptionVM)
                    .onTapGesture { historyVM.selectedSession = live }
                Divider()
            }

            // ── Session list ───────────────────────────────────────────────
            if historyVM.isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading sessions…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else if historyVM.filteredSessions.isEmpty {
                EmptyHistoryView(isSearching: !historyVM.searchQuery.isEmpty)
            } else {
                List(selection: $historyVM.selectedSession) {
                    // Pinned Group
                    if !pinnedSessions.isEmpty {
                        Section(header: sectionHeader(title: "Pinned", icon: "pin.fill", count: pinnedSessions.count)) {
                            ForEach(pinnedSessions) { session in
                                SessionRow(session: session, isPinned: true)
                                    .tag(session)
                                    .contextMenu { contextMenu(for: session) }
                            }
                        }
                    }

                    // Today Group
                    if !todaySessions.isEmpty {
                        Section(header: sectionHeader(title: "Today", icon: "calendar", count: todaySessions.count)) {
                            ForEach(todaySessions) { session in
                                SessionRow(session: session, isPinned: false)
                                    .tag(session)
                                    .contextMenu { contextMenu(for: session) }
                            }
                        }
                    }

                    // Yesterday Group
                    if !yesterdaySessions.isEmpty {
                        Section(header: sectionHeader(title: "Yesterday", icon: "clock.arrow.circlepath", count: yesterdaySessions.count)) {
                            ForEach(yesterdaySessions) { session in
                                SessionRow(session: session, isPinned: false)
                                    .tag(session)
                                    .contextMenu { contextMenu(for: session) }
                            }
                        }
                    }

                    // Past 7 Days Group
                    if !pastWeekSessions.isEmpty {
                        Section(header: sectionHeader(title: "Previous 7 Days", icon: "calendar.badge.clock", count: pastWeekSessions.count)) {
                            ForEach(pastWeekSessions) { session in
                                SessionRow(session: session, isPinned: false)
                                    .tag(session)
                                    .contextMenu { contextMenu(for: session) }
                            }
                        }
                    }

                    // Older Group
                    if !olderSessions.isEmpty {
                        Section(header: sectionHeader(title: "Older", icon: "archivebox", count: olderSessions.count)) {
                            ForEach(olderSessions) { session in
                                SessionRow(session: session, isPinned: false)
                                    .tag(session)
                                    .contextMenu { contextMenu(for: session) }
                            }
                        }
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

    // MARK: - Section Header View

    private func sectionHeader(title: String, icon: String, count: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.vertical, 2)
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

        Button {
            togglePin(session)
        } label: {
            Label(isPinned(session) ? "Unpin from Top" : "Pin to Top", systemImage: isPinned(session) ? "pin.slash" : "pin")
        }

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
    let isPinned: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Icon badge with subtle gradient
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.2), Color.accentColor.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                Image(systemName: isPinned ? "pin.fill" : "waveform")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(session.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)

                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 4) {
                    Text(session.formattedDate)
                        .lineLimit(1)
                    Text("·")
                    Text(session.formattedDuration)
                        .lineLimit(1)
                    if session.wordCount > 0 {
                        Text("·")
                        Text("\(session.wordCount)w")
                            .lineLimit(1)
                    }
                    Spacer(minLength: 2)
                    Text(session.languageLabel.uppercased())
                        .font(.system(size: 8.5, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
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
                    .frame(width: 34, height: 34)
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .scaleEffect(vm.isPaused ? 0.8 : 1.25)
                    .animation(.easeInOut(duration: 0.6).repeatForever(), value: vm.isPaused)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("● LIVE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.red)
                    if vm.isPaused {
                        Text("(PAUSED)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                }
                Text(session.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Text("\(vm.liveSegments.count) segments transcribed")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.08))
    }
}

// MARK: - Empty state

private struct EmptyHistoryView: View {
    let isSearching: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isSearching ? "magnifyingglass" : "waveform.slash")
                .font(.system(size: 32))
                .foregroundStyle(.secondary.opacity(0.7))
            Text(isSearching ? "No Matching Sessions" : "No Sessions Yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(isSearching ? "Try searching for a different keyword." : "Press ⇧⌘N to start a new recording.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
