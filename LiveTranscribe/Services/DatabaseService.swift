// DatabaseService.swift
// LiveTranscribe
//
// SQLite storage for transcript sessions and segments.
// Uses the built-in libsqlite3 C API (no external dependencies).

import Foundation
import SQLite3

// MARK: - Error

enum DatabaseError: LocalizedError {
    case openFailed(String)
    case queryFailed(String)
    case notFound

    var errorDescription: String? {
        switch self {
        case .openFailed(let m):  return "Could not open database: \(m)"
        case .queryFailed(let m): return "Database query failed: \(m)"
        case .notFound:           return "Record not found."
        }
    }
}

// MARK: - DatabaseService

/// Thread-safe SQLite wrapper for sessions and segments.
final class DatabaseService {

    // MARK: Singleton
    static let shared = DatabaseService()

    // MARK: Private
    private var db: OpaquePointer?
    private let queue = DispatchQueue(
        label: "com.livetranscribe.database", qos: .utility)

    // MARK: - Initialisation

    private init() {
        queue.sync {
            do {
                try openDatabase()
                try createSchema()
            } catch {
                print("[DB] Init error: \(error)")
            }
        }
    }

    // MARK: - Setup

    private var databaseURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir  = base.appendingPathComponent("LiveTranscribe")
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("transcripts.sqlite")
    }

    private func openDatabase() throws {
        let path = databaseURL.path
        guard sqlite3_open_v2(
            path, &db,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK else {
            throw DatabaseError.openFailed(dbErrorMessage())
        }
        // Performance pragmas
        _ = try? execSQL("PRAGMA journal_mode=WAL;")
        _ = try? execSQL("PRAGMA synchronous=NORMAL;")
        _ = try? execSQL("PRAGMA foreign_keys=ON;")
        _ = try? execSQL("PRAGMA cache_size=-8000;")  // 8 MB page cache
    }

    private func createSchema() throws {
        try execSQL("""
            CREATE TABLE IF NOT EXISTS sessions (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                title       TEXT    NOT NULL,
                started_at  REAL    NOT NULL,
                ended_at    REAL,
                model_used  TEXT    NOT NULL DEFAULT 'base',
                language    TEXT    NOT NULL DEFAULT 'auto',
                created_at  REAL    NOT NULL
            );
        """)
        try execSQL("""
            CREATE TABLE IF NOT EXISTS segments (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id  INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
                text        TEXT    NOT NULL,
                start_time  REAL    NOT NULL DEFAULT 0,
                end_time    REAL    NOT NULL DEFAULT 0,
                language    TEXT    NOT NULL DEFAULT '',
                created_at  REAL    NOT NULL
            );
        """)
        try execSQL("""
            CREATE INDEX IF NOT EXISTS idx_segments_session
            ON segments (session_id);
        """)
    }

    // MARK: - Session CRUD

    func createSession(
        title: String,
        modelUsed: String,
        language: String
    ) throws -> TranscriptSession {
        var result: TranscriptSession?
        var err: Error?
        queue.sync {
            do {
                let now = Date().timeIntervalSince1970
                let sql = """
                    INSERT INTO sessions (title, started_at, model_used, language, created_at)
                    VALUES (?, ?, ?, ?, ?);
                """
                let stmt = try prepare(sql)
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_text(stmt, 1, title, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(stmt, 2, now)
                sqlite3_bind_text(stmt, 3, modelUsed, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 4, language,  -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(stmt, 5, now)
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw DatabaseError.queryFailed(self.dbErrorMessage())
                }
                let rowID = sqlite3_last_insert_rowid(self.db)
                result = TranscriptSession(
                    id: rowID, title: title,
                    startedAt: Date(timeIntervalSince1970: now),
                    endedAt: nil,
                    modelUsed: modelUsed,
                    language: language,
                    segments: []
                )
            } catch { err = error }
        }
        if let err { throw err }
        return result!
    }

    func updateSessionEnd(id: Int64, endedAt: Date) throws {
        try queue.sync {
            let sql = "UPDATE sessions SET ended_at = ? WHERE id = ?;"
            let stmt = try prepare(sql)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_double(stmt, 1, endedAt.timeIntervalSince1970)
            sqlite3_bind_int64(stmt,  2, id)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DatabaseError.queryFailed(dbErrorMessage())
            }
        }
    }

    func resumeSession(id: Int64) throws {
        try queue.sync {
            let sql = "UPDATE sessions SET ended_at = NULL WHERE id = ?;"
            let stmt = try prepare(sql)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, id)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DatabaseError.queryFailed(dbErrorMessage())
            }
        }
    }

    func updateSessionTitle(_ title: String, id: Int64) throws {
        try queue.sync {
            let sql = "UPDATE sessions SET title = ? WHERE id = ?;"
            let stmt = try prepare(sql)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, id)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DatabaseError.queryFailed(dbErrorMessage())
            }
        }
    }

    func fetchAllSessions() throws -> [TranscriptSession] {
        var rows: [TranscriptSession] = []
        var err: Error?
        queue.sync {
            do {
                let sql = """
                    SELECT id, title, started_at, ended_at, model_used, language
                    FROM sessions ORDER BY started_at DESC;
                """
                let stmt = try self.prepare(sql)
                defer { sqlite3_finalize(stmt) }
                while sqlite3_step(stmt) == SQLITE_ROW {
                    rows.append(self.sessionFrom(stmt: stmt, segments: []))
                }
            } catch { err = error }
        }
        if let err { throw err }
        return rows
    }

    func deleteSession(id: Int64) throws {
        try queue.sync {
            let sql = "DELETE FROM sessions WHERE id = ?;"
            let stmt = try prepare(sql)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, id)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DatabaseError.queryFailed(dbErrorMessage())
            }
        }
    }

    // MARK: - Segment CRUD

    func insertSegment(_ segment: TranscriptSegment) throws -> TranscriptSegment {
        var result: TranscriptSegment?
        var err: Error?
        queue.sync {
            do {
                let now = Date().timeIntervalSince1970
                let sql = """
                    INSERT INTO segments
                        (session_id, text, start_time, end_time, language, created_at)
                    VALUES (?, ?, ?, ?, ?, ?);
                """
                let stmt = try self.prepare(sql)
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_int64(stmt,  1, segment.sessionId)
                sqlite3_bind_text(stmt,   2, segment.text, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(stmt, 3, segment.startTime)
                sqlite3_bind_double(stmt, 4, segment.endTime)
                sqlite3_bind_text(stmt,   5, segment.language, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(stmt, 6, now)
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw DatabaseError.queryFailed(self.dbErrorMessage())
                }
                let rowID = sqlite3_last_insert_rowid(self.db)
                var updated = segment
                updated.id        = rowID
                updated.createdAt = Date(timeIntervalSince1970: now)
                result = updated
            } catch { err = error }
        }
        if let err { throw err }
        return result!
    }

    func fetchSegments(for sessionId: Int64) throws -> [TranscriptSegment] {
        var rows: [TranscriptSegment] = []
        var err: Error?
        queue.sync {
            do {
                let sql = """
                    SELECT id, session_id, text, start_time, end_time, language, created_at
                    FROM segments WHERE session_id = ?
                    ORDER BY start_time ASC;
                """
                let stmt = try self.prepare(sql)
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_int64(stmt, 1, sessionId)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    rows.append(self.segmentFrom(stmt: stmt))
                }
            } catch { err = error }
        }
        if let err { throw err }
        return rows
    }

    // MARK: - Helpers

    @discardableResult
    private func execSQL(_ sql: String) throws -> Bool {
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errMsg)
            throw DatabaseError.queryFailed(msg)
        }
        return true
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(dbErrorMessage())
        }
        return stmt
    }

    private func dbErrorMessage() -> String {
        guard let db = db else { return "No database" }
        return String(cString: sqlite3_errmsg(db))
    }

    private func sessionFrom(
        stmt: OpaquePointer?, segments: [TranscriptSegment]
    ) -> TranscriptSession {
        let id        = sqlite3_column_int64(stmt, 0)
        let title     = String(cString: sqlite3_column_text(stmt, 1))
        let startedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
        let endedAtRaw = sqlite3_column_double(stmt, 3)
        let endedAt: Date? = sqlite3_column_type(stmt, 3) == SQLITE_NULL
                             ? nil
                             : Date(timeIntervalSince1970: endedAtRaw)
        let model     = String(cString: sqlite3_column_text(stmt, 4))
        let lang      = String(cString: sqlite3_column_text(stmt, 5))
        return TranscriptSession(
            id: id, title: title, startedAt: startedAt,
            endedAt: endedAt, modelUsed: model, language: lang,
            segments: segments
        )
    }

    private func segmentFrom(stmt: OpaquePointer?) -> TranscriptSegment {
        let id        = sqlite3_column_int64(stmt, 0)
        let sessionId = sqlite3_column_int64(stmt, 1)
        let text      = String(cString: sqlite3_column_text(stmt, 2))
        let start     = sqlite3_column_double(stmt, 3)
        let end       = sqlite3_column_double(stmt, 4)
        let lang      = String(cString: sqlite3_column_text(stmt, 5))
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6))
        return TranscriptSegment(
            id: id, sessionId: sessionId, text: text,
            startTime: start, endTime: end,
            language: lang, createdAt: createdAt
        )
    }
}

// Needed for SQLITE_TRANSIENT workaround in Swift
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
