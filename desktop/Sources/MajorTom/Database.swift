import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum DatabaseError: Error, CustomStringConvertible {
    case open(String)
    case query(String)

    var description: String {
        switch self {
        case .open(let m): return "open: \(m)"
        case .query(let m): return "query: \(m)"
        }
    }
}

/// Both the app and the native messaging host open this same file. WAL mode is
/// what makes that safe: the host can append while the app is reading.
final class Database {
    static let fileURL: URL = {
        if let override = ProcessInfo.processInfo.environment["MAJORTOM_DB"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return AppPaths.dataDirectory.appendingPathComponent("majortom.sqlite")
    }()

    private var db: OpaquePointer?

    init(url: URL = Database.fileURL) throws {
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

    func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw DatabaseError.query("\(lastError) — \(sql)")
        }
    }

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

        // Additive migrations for databases created before a column existed.
        // Every one of these is owned by the app, so none of the writers'
        // `ON CONFLICT ... DO UPDATE` clauses may touch them.
        let added = [
            ("status", "TEXT NOT NULL DEFAULT 'learning'"),
            // Soft delete: a hard delete would come straight back on the next
            // browser resend, which carries the whole vocabulary every time.
            ("removed_at", "TEXT"),
            ("review_streak", "INTEGER NOT NULL DEFAULT 0"),
            ("review_due", "TEXT"),
            // German alternatives from the model, one per line.
            ("alternatives", "TEXT NOT NULL DEFAULT ''"),
            // How the word sits in today's German, empty when it is ordinary.
            ("register", "TEXT NOT NULL DEFAULT ''"),
            // A note from the model, only for words where one matters.
            ("usage_note", "TEXT NOT NULL DEFAULT ''"),
            // When the model last looked at the word. Words translated by the
            // browser, or before notes existed, are still null.
            ("enriched_at", "TEXT"),
        ]
        for (column, definition) in added where !columnExists("item", column) {
            try exec("ALTER TABLE item ADD COLUMN \(column) \(definition);")
        }
        // A name you gave a source. `title` cannot be renamed in place: the
        // browser and the phone find a source again by it when they resync.
        if !columnExists("source", "display_title") {
            try exec("ALTER TABLE source ADD COLUMN display_title TEXT NOT NULL DEFAULT '';")
        }

        try exec("""
            CREATE TABLE IF NOT EXISTS review (
                id      INTEGER PRIMARY KEY,
                item_id INTEGER NOT NULL REFERENCES item(id) ON DELETE CASCADE,
                correct INTEGER NOT NULL,
                at      TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS review_at ON review(at);
            """)

        // Conversations with the model, most about one word. Kept so a
        // question asked while reviewing can be picked up again later.
        try exec("""
            CREATE TABLE IF NOT EXISTS chat (
                id         INTEGER PRIMARY KEY,
                item_id    INTEGER REFERENCES item(id) ON DELETE SET NULL,
                title      TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS chat_item ON chat(item_id);

            CREATE TABLE IF NOT EXISTS chat_message (
                id      INTEGER PRIMARY KEY,
                chat_id INTEGER NOT NULL REFERENCES chat(id) ON DELETE CASCADE,
                role    TEXT NOT NULL,
                content TEXT NOT NULL,
                at      TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS chat_message_chat ON chat_message(chat_id);
            """)
    }

    private func columnExists(_ table: String, _ column: String) -> Bool {
        let names = (try? query("PRAGMA table_info(\(table));") { $0.string(1) }) ?? []
        return names.contains(column)
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
    func run(_ sql: String, _ binds: [Any?] = []) throws -> Int64 {
        let stmt = try prepare(sql, binds)
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw DatabaseError.query("\(lastError) — \(sql)")
        }
        return sqlite3_last_insert_rowid(db)
    }

    func query<T>(_ sql: String, _ binds: [Any?] = [], _ row: (Row) -> T) throws -> [T] {
        let stmt = try prepare(sql, binds)
        defer { sqlite3_finalize(stmt) }
        var out: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW { out.append(row(Row(stmt))) }
        return out
    }

    struct Row {
        private let stmt: OpaquePointer
        init(_ stmt: OpaquePointer) { self.stmt = stmt }

        func int(_ i: Int32) -> Int64 { sqlite3_column_int64(stmt, i) }
        func double(_ i: Int32) -> Double { sqlite3_column_double(stmt, i) }
        func bool(_ i: Int32) -> Bool { sqlite3_column_int64(stmt, i) != 0 }
        func isNull(_ i: Int32) -> Bool { sqlite3_column_type(stmt, i) == SQLITE_NULL }
        func string(_ i: Int32) -> String {
            guard let c = sqlite3_column_text(stmt, i) else { return "" }
            return String(cString: c)
        }
        func date(_ i: Int32) -> Date { ISO8601.parse(string(i)) }
    }
}

enum ISO8601 {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()

    static func parse(_ s: String) -> Date {
        withFraction.date(from: s) ?? plain.date(from: s) ?? .distantPast
    }

    static func string(_ d: Date = Date()) -> String { withFraction.string(from: d) }
}
