// The library lives on the Mac. The phone sends words there rather than
// keeping its own copy, so none of this is built for iOS.
#if os(macOS)
import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum DatabaseError: Error, CustomStringConvertible {
    case open(String)
    case query(String)

    public var description: String {
        switch self {
        case .open(let m): return "could not open the database at \(m)"
        case .query(let m): return "query: \(m)"
        }
    }
}

/// Writes into the same SQLite file the MajorTom desktop app reads, so saved
/// call words show up under its Calls tab with no import step.
///
/// The desktop app owns the schema; everything here is additive. It polls for
/// external writes every three seconds, so rows appear while it is running.
/// Safe to share across threads: the handle is opened `SQLITE_OPEN_FULLMUTEX`,
/// so SQLite serialises access to it internally.
public final class Database: @unchecked Sendable {
    /// `MAJORTOM_DB` wins, then `data/` at the monorepo root, then a private
    /// copy. Finding the root by walking up means this works wherever the repo
    /// is checked out, and it is the same marker the desktop app looks for.
    public static func defaultURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["MAJORTOM_DB"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        if let root = repoRoot() {
            return root.appending(path: "data/majortom.sqlite")
        }

        let fallback = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/MajorTom")
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback.appending(path: "majortom.sqlite")
    }

    private static func repoRoot() -> URL? {
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
        while dir.path != "/" {
            if fm.fileExists(atPath: dir.appending(path: "extension/package.json").path) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    private var db: OpaquePointer?

    public init(url: URL = Database.defaultURL()) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            throw DatabaseError.open(url.path)
        }
        db = handle
        sqlite3_busy_timeout(handle, 5_000)
        try exec("PRAGMA journal_mode=WAL;")
        try exec("PRAGMA foreign_keys=ON;")
        try migrate()
    }

    deinit { if let db { sqlite3_close_v2(db) } }

    private var lastError: String {
        db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "no handle"
    }

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw DatabaseError.query("\(lastError) — \(sql)")
        }
    }

    /// Creates the tables if this is a fresh file, matching the desktop app's
    /// own definitions, and adds the one column calls need.
    private func migrate() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS source (
                id         INTEGER PRIMARY KEY,
                kind       TEXT NOT NULL,
                title      TEXT NOT NULL,
                site       TEXT NOT NULL DEFAULT '',
                url        TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                UNIQUE(kind, url, title)
            );

            CREATE TABLE IF NOT EXISTS item (
                id                  INTEGER PRIMARY KEY,
                source_id           INTEGER NOT NULL REFERENCES source(id) ON DELETE CASCADE,
                kind                TEXT NOT NULL,
                text                TEXT NOT NULL,
                translation         TEXT NOT NULL DEFAULT '',
                context             TEXT NOT NULL DEFAULT '',
                context_translation TEXT NOT NULL DEFAULT '',
                position            REAL NOT NULL DEFAULT 0,
                starred             INTEGER NOT NULL DEFAULT 0,
                status              TEXT NOT NULL DEFAULT 'learning',
                created_at          TEXT NOT NULL,
                UNIQUE(source_id, kind, text)
            );

            CREATE INDEX IF NOT EXISTS item_source ON item(source_id, kind);
            """)

        // 'mac' or 'phone' — a word saved in person arrives untranslated and is
        // filled in on sync, and it is worth being able to tell which is which.
        if !columnExists("source", "origin") {
            try exec("ALTER TABLE source ADD COLUMN origin TEXT NOT NULL DEFAULT 'mac';")
        }
        // Owned by the library app; added here too so the query below works on
        // a file this package created first.
        if !columnExists("item", "removed_at") {
            try exec("ALTER TABLE item ADD COLUMN removed_at TEXT;")
        }
        // German alternatives from the model, one per line.
        if !columnExists("item", "alternatives") {
            try exec("ALTER TABLE item ADD COLUMN alternatives TEXT NOT NULL DEFAULT '';")
        }
    }

    private func columnExists(_ table: String, _ column: String) -> Bool {
        let names = (try? query("PRAGMA table_info(\(table));") { $0.string(1) }) ?? []
        return names.contains(column)
    }

    // MARK: - Writing

    /// The one source holding words typed in by hand, on the Mac or the phone.
    /// Same row the library app creates, so both land in one "My words" list.
    public func ownWordsSource() throws -> Int64 {
        let ids = try query(
            """
            INSERT INTO source (kind, title, site, url, created_at)
            VALUES ('own', 'My words', '', 'own', ?)
            ON CONFLICT(kind, url, title) DO UPDATE SET kind = kind
            RETURNING id;
            """,
            [ISO8601.string()]
        ) { $0.int(0) }
        guard let id = ids.first else {
            throw DatabaseError.query("own-words source upsert returned no id")
        }
        return id
    }

    /// One call or one in-person session. `url` carries a stable UUID so that
    /// syncing the same session twice updates it instead of duplicating it.
    @discardableResult
    public func upsertSource(
        title: String,
        person: String,
        sessionID: String,
        origin: String = "mac",
        createdAt: Date = Date()
    ) throws -> Int64 {
        let ids = try query(
            """
            INSERT INTO source (kind, title, site, url, created_at, origin)
            VALUES ('call', ?, ?, ?, ?, ?)
            ON CONFLICT(kind, url, title) DO UPDATE SET site = excluded.site
            RETURNING id;
            """,
            [title, person, sessionID, ISO8601.string(createdAt), origin]
        ) { $0.int(0) }

        guard let id = ids.first else {
            throw DatabaseError.query("source upsert returned no id")
        }
        return id
    }

    /// Saving the same word twice in one session updates it rather than
    /// failing. A resend with no translation keeps the one already filled in.
    public func upsertItem(
        sourceID: Int64,
        text: String,
        translation: String,
        context: String,
        contextTranslation: String = "",
        position: TimeInterval,
        createdAt: Date = Date()
    ) throws {
        let kind = text.contains(" ") ? "phrase" : "word"
        try run(
            """
            INSERT INTO item (source_id, kind, text, translation, context,
                              context_translation, position, starred, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?)
            ON CONFLICT(source_id, kind, text) DO UPDATE SET
                translation = COALESCE(NULLIF(excluded.translation, ''), item.translation),
                context = excluded.context,
                context_translation = COALESCE(
                    NULLIF(excluded.context_translation, ''), item.context_translation);
            """,
            [sourceID, kind, text, translation, context, contextTranslation, position,
             ISO8601.string(createdAt)]
        )
    }

    public func deleteItem(sourceID: Int64, text: String) throws {
        try run("DELETE FROM item WHERE source_id = ? AND text = ?;", [sourceID, text])
    }

    /// Everything still waiting for a translation, across every source. Words
    /// saved on the phone arrive untranslated and the model is often not
    /// running when they land, so the backlog has to be drainable later rather
    /// than only at the moment of import.
    public func untranslatedItems() throws -> [(id: Int64, text: String, context: String)] {
        try query(
            "SELECT id, text, context FROM item WHERE translation = '' AND removed_at IS NULL ORDER BY id;"
        ) { ($0.int(0), $0.string(1), $0.string(2)) }
    }

    /// Items still waiting for a translation — what the phone produces, and
    /// what the fill-in pass consumes.
    public func untranslatedItems(sourceID: Int64) throws -> [(id: Int64, text: String, context: String)] {
        try query(
            "SELECT id, text, context FROM item WHERE source_id = ? AND translation = '' ORDER BY id;",
            [sourceID]
        ) { ($0.int(0), $0.string(1), $0.string(2)) }
    }

    public func setTranslation(
        itemID: Int64, translation: String, contextTranslation: String, alternatives: [String] = []
    ) throws {
        try run(
            "UPDATE item SET translation = ?, context_translation = ?, alternatives = ? WHERE id = ?;",
            [translation, contextTranslation, alternatives.joined(separator: "\n"), itemID]
        )
    }

    // MARK: - Statement helpers

    private func prepare(_ sql: String, _ binds: [Any?]) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw DatabaseError.query("\(lastError) — \(sql)")
        }
        for (i, value) in binds.enumerated() {
            let idx = Int32(i + 1)
            switch value {
            case nil: sqlite3_bind_null(stmt, idx)
            case let v as String: sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
            case let v as Int64: sqlite3_bind_int64(stmt, idx, v)
            case let v as Int: sqlite3_bind_int64(stmt, idx, Int64(v))
            case let v as Double: sqlite3_bind_double(stmt, idx, v)
            case let v as Bool: sqlite3_bind_int64(stmt, idx, v ? 1 : 0)
            default: sqlite3_bind_text(stmt, idx, "\(value!)", -1, SQLITE_TRANSIENT)
            }
        }
        return stmt
    }

    @discardableResult
    private func run(_ sql: String, _ binds: [Any?] = []) throws -> Int64 {
        let stmt = try prepare(sql, binds)
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw DatabaseError.query("\(lastError) — \(sql)")
        }
        return sqlite3_last_insert_rowid(db)
    }

    private func query<T>(_ sql: String, _ binds: [Any?] = [], _ row: (Row) -> T) throws -> [T] {
        let stmt = try prepare(sql, binds)
        defer { sqlite3_finalize(stmt) }
        var out: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW { out.append(row(Row(stmt))) }
        return out
    }

    public struct Row {
        private let stmt: OpaquePointer
        init(_ stmt: OpaquePointer) { self.stmt = stmt }

        func int(_ i: Int32) -> Int64 { sqlite3_column_int64(stmt, i) }
        func double(_ i: Int32) -> Double { sqlite3_column_double(stmt, i) }
        func string(_ i: Int32) -> String {
            guard let c = sqlite3_column_text(stmt, i) else { return "" }
            return String(cString: c)
        }
    }
}

public enum ISO8601 {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public static func string(_ d: Date = Date()) -> String { withFraction.string(from: d) }
}
#endif
