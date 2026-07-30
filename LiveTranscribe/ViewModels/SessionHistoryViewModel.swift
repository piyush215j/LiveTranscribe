// SessionHistoryViewModel.swift
// LiveTranscribe
//
// Loads and manages the list of past transcript sessions from SQLite.

import Foundation
import Combine

@MainActor
final class SessionHistoryViewModel: ObservableObject {

    // MARK: - Published state

    @Published private(set) var sessions: [TranscriptSession] = []
    @Published private(set) var isLoading = false
    @Published var selectedSession: TranscriptSession?
    @Published var searchQuery = ""

    // MARK: - Private

    private let db = DatabaseService.shared

    // MARK: - Init

    init() {
        Task { await loadSessions() }
    }

    // MARK: - Load

    func loadSessions() async {
        isLoading = true
        defer { isLoading = false }

        do {
            var loaded = try db.fetchAllSessions()
            // Attach segments to each session
            for i in loaded.indices {
                loaded[i].segments = (try? db.fetchSegments(for: loaded[i].id)) ?? []
            }
            sessions = loaded
        } catch {
            print("[HistoryVM] Load error: \(error)")
        }
    }

    /// Select a session and load its full segment list
    func select(_ session: TranscriptSession) {
        var s = session
        if s.segments.isEmpty {
            s.segments = (try? db.fetchSegments(for: s.id)) ?? []
        }
        selectedSession = s
    }

    // MARK: - Filtered list

    var filteredSessions: [TranscriptSession] {
        guard !searchQuery.isEmpty else { return sessions }
        let q = searchQuery.lowercased()
        return sessions.filter {
            $0.title.lowercased().contains(q) ||
            $0.segments.contains { $0.text.lowercased().contains(q) }
        }
    }

    // MARK: - Mutations

    func addSession(_ session: TranscriptSession) {
        sessions.insert(session, at: 0)
    }

    func updateSession(_ session: TranscriptSession) {
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        }
        if selectedSession?.id == session.id {
            selectedSession = session
        }
    }

    func deleteSession(_ session: TranscriptSession) {
        do {
            try db.deleteSession(id: session.id)
            sessions.removeAll { $0.id == session.id }
            if selectedSession?.id == session.id {
                selectedSession = nil
            }
        } catch {
            print("[HistoryVM] Delete error: \(error)")
        }
    }

    func renameSession(_ session: TranscriptSession, to newTitle: String) {
        do {
            try db.updateSessionTitle(newTitle, id: session.id)
            if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[idx].title = newTitle
            }
            if selectedSession?.id == session.id {
                selectedSession?.title = newTitle
            }
        } catch {
            print("[HistoryVM] Rename error: \(error)")
        }
    }

    // MARK: - Export helper

    func export(session: TranscriptSession, format: ExportFormat) -> URL? {
        var s = session
        if s.segments.isEmpty {
            s.segments = (try? db.fetchSegments(for: s.id)) ?? []
        }
        let dir = URL(fileURLWithPath: AppSettings.shared.exportFolderPath)
        return try? ExportService.shared.export(session: s, format: format, to: dir)
    }
}
