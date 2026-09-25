import Foundation

/// Chrome/Brave spawn this binary with `--native-host` and talk over stdio:
/// a 4-byte native-endian length, then that many bytes of UTF-8 JSON.
/// Because the browser spawns us on demand, the app need not be running to
/// receive saves.
enum NativeHost {
    static func run() -> Never {
        let stdin = FileHandle.standardInput
        let stdout = FileHandle.standardOutput

        while let body = readMessage(stdin) {
            let reply = handle(body)
            var length = UInt32(reply.count)
            stdout.write(Data(bytes: &length, count: 4))
            stdout.write(reply)
        }
        exit(0)
    }

    private static func readMessage(_ handle: FileHandle) -> Data? {
        guard let header = try? handle.read(upToCount: 4), header.count == 4 else { return nil }
        let length = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        guard length > 0, length <= 64 * 1024 * 1024 else { return nil }

        var body = Data()
        while body.count < Int(length) {
            guard let chunk = try? handle.read(upToCount: Int(length) - body.count),
                  !chunk.isEmpty else { return nil }
            body.append(chunk)
        }
        return body
    }

    private static func handle(_ body: Data) -> Data {
        let response: SyncResponse
        do {
            let request = try JSONDecoder().decode(SyncRequest.self, from: body)
            switch request.type {
            case "sync":
                let written = try apply(
                    entries: request.entries ?? [],
                    mutations: request.mutations ?? []
                )
                response = SyncResponse(ok: true, written: written, error: nil)
            case "ping":
                response = SyncResponse(ok: true, written: 0, error: nil)
            default:
                response = SyncResponse(ok: false, written: nil, error: "unknown type \(request.type)")
            }
        } catch {
            response = SyncResponse(ok: false, written: nil, error: "\(error)")
        }
        return (try? JSONEncoder().encode(response)) ?? Data("{\"ok\":false}".utf8)
    }

    /// Upserts, so the extension can safely resend its whole vocabulary and a
    /// first sync doubles as the initial import.
    ///
    /// An empty translation never overwrites a filled one: the browser sends
    /// blanks when the local model is down, and the library may have filled them since.
    ///
    /// Deliberately does not update `starred` on conflict. The browser only
    /// ever reports what it knows, so resending would wipe anything starred in
    /// the app; the browser seeds the flag, the app owns it from then on.
    private static func apply(entries: [IncomingEntry], mutations: [Mutation]) throws -> Int {
        guard !entries.isEmpty || !mutations.isEmpty else { return 0 }
        let db = try Database()
        try db.exec("BEGIN IMMEDIATE;")

        // Mutations run first so that the entries — which are the browser's
        // current state — win over any stale queued change.
        for mutation in mutations {
            switch mutation.kind {
            case "delete":
                try db.run("""
                    DELETE FROM item WHERE kind IN ('word', 'phrase') AND text = ? AND source_id IN
                        (SELECT id FROM source WHERE kind = 'show' AND url = ?)
                    """, [mutation.word, mutation.url])
            case "star":
                try db.run("""
                    UPDATE item SET starred = ? WHERE kind IN ('word', 'phrase') AND text = ? AND source_id IN
                        (SELECT id FROM source WHERE kind = 'show' AND url = ?)
                    """, [mutation.starred ?? false, mutation.word, mutation.url])
            default:
                break
            }
        }

        var sourceIDs: [String: Int64] = [:]
        var written = 0

        for entry in entries {
            let url = entry.url ?? ""
            let title = (entry.title?.isEmpty == false ? entry.title! : url)
            guard !entry.word.isEmpty, !title.isEmpty else { continue }
            let createdAt = entry.createdAt ?? ISO8601.string()

            let key = "\(url)\u{0}\(title)"
            let sourceID: Int64
            if let cached = sourceIDs[key] {
                sourceID = cached
            } else {
                try db.run("""
                    INSERT INTO source (kind, title, site, url, created_at)
                    VALUES ('show', ?, ?, ?, ?)
                    ON CONFLICT(kind, url, title) DO NOTHING
                    """, [title, entry.site ?? "", url, createdAt])
                let found = try db.query(
                    "SELECT id FROM source WHERE kind = 'show' AND url = ? AND title = ?",
                    [url, title]
                ) { $0.int(0) }
                guard let id = found.first else { continue }
                sourceID = id
                sourceIDs[key] = id
            }

            try db.run("""
                INSERT INTO item (source_id, kind, text, translation, context,
                                  context_translation, position, starred, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(source_id, kind, text) DO UPDATE SET
                    translation = COALESCE(NULLIF(excluded.translation, ''), item.translation),
                    context = COALESCE(NULLIF(item.context, ''), excluded.context),
                    context_translation = COALESCE(
                        NULLIF(excluded.context_translation, ''), item.context_translation),
                    position = excluded.position
                """, [
                    // Shift-clicked phrases arrive in the same list; the
                    // calls app and the reMarkable make the same split.
                    sourceID, entry.word.contains(" ") ? "phrase" : "word",
                    entry.word, entry.translation ?? "", entry.context ?? "",
                    entry.contextTranslation ?? "", entry.time ?? 0,
                    entry.starred ?? false, createdAt,
                ])
            written += 1
        }

        // A show you have unsaved every word from should not keep a card.
        try db.exec("""
            DELETE FROM source WHERE kind = 'show'
              AND id NOT IN (SELECT source_id FROM item);
            """)

        try db.exec("COMMIT;")
        return written
    }
}
