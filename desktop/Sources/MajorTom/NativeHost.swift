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
                let written = try write(request.entries ?? [])
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

    /// Upserts, so the extension can safely resend its whole vocabulary: edits
    /// and stars propagate, and a first sync doubles as the initial import.
    private static func write(_ entries: [IncomingEntry]) throws -> Int {
        guard !entries.isEmpty else { return 0 }
        let db = try Database()
        try db.exec("BEGIN IMMEDIATE;")

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
                VALUES (?, 'word', ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(source_id, kind, text) DO UPDATE SET
                    translation = excluded.translation,
                    context = excluded.context,
                    context_translation = excluded.context_translation,
                    position = excluded.position,
                    starred = excluded.starred
                """, [
                    sourceID, entry.word, entry.translation ?? "", entry.context ?? "",
                    entry.contextTranslation ?? "", entry.time ?? 0,
                    entry.starred ?? false, createdAt,
                ])
            written += 1
        }

        try db.exec("COMMIT;")
        return written
    }
}
