import Foundation
import SwiftUI

/// Reads the shared database and republishes it to the UI. Other processes
/// write behind our back, so we re-check cheaply on a timer and on focus.
@MainActor
final class Store: ObservableObject {
    @Published private(set) var sources: [Source] = []
    @Published private(set) var stats = Stats()
    @Published private(set) var loadError: String?
    /// Bumped when a chat changes, so the AI tab re-reads its list.
    @Published private(set) var chatsVersion = 0

    private var db: Database?
    private var fingerprint = ""
    private var timer: Timer?

    /// Columns every item query selects, in the order `item(_:)` reads them.
    private static let itemColumns = """
        i.id, i.source_id, s.kind, COALESCE(NULLIF(s.display_title, ''), s.title), s.url, i.kind, i.text, i.translation,
        i.context, i.context_translation, i.position, i.starred, i.status, i.created_at,
        i.alternatives, i.register, i.usage_note
        """

    init() {
        do {
            db = try Database()
        } catch {
            loadError = "\(error)"
        }
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reloadIfChanged() }
        }
    }

    deinit { timer?.invalidate() }

    // MARK: - Sources

    /// Most recently saved-into first, so callers can take a prefix for
    /// "recent" without another query.
    func sources(of kind: SourceKind) -> [Source] {
        sources.filter { $0.kind == kind }
    }

    func sources(of kind: SourceKind, site: String) -> [Source] {
        sources.filter { $0.kind == kind && $0.site == site }
    }

    func platforms(of kind: SourceKind) -> [Platform] {
        Dictionary(grouping: sources(of: kind), by: \.site)
            .map { site, group in
                Platform(
                    id: site,
                    showCount: group.count,
                    wordCount: group.reduce(0) { $0 + $1.itemCount },
                    lastSavedAt: group.map(\.lastSavedAt).max() ?? .distantPast)
            }
            .sorted { $0.lastSavedAt > $1.lastSavedAt }
    }

    // MARK: - Items

    func items(in source: Source) -> [Item] {
        queryItems("WHERE i.source_id = ? ORDER BY i.position, i.id", [source.id])
    }

    func allItems() -> [Item] {
        queryItems("ORDER BY i.created_at DESC")
    }

    /// Words with no meaning yet.
    func untranslatedItems(in scope: Scope = .all) -> [Item] {
        switch scope {
        case .all:
            return queryItems("WHERE i.translation = '' ORDER BY i.id")
        case .kind(let kind):
            return queryItems("WHERE i.translation = '' AND s.kind = ? ORDER BY i.id", [kind.rawValue])
        case .source(let source):
            return queryItems("WHERE i.translation = '' AND i.source_id = ? ORDER BY i.id", [source.id])
        }
    }

    func recentItems(limit: Int) -> [Item] {
        queryItems("ORDER BY i.created_at DESC LIMIT ?", [limit])
    }

    /// Words ready to review: still being learned, translated (a card with no
    /// answer is useless), and due. Oldest-due first, never-reviewed after.
    func dueItems(in source: Source? = nil, limit: Int = 20) -> [Item] {
        var filter = """
            WHERE i.status = 'learning' AND i.translation != ''
              AND (i.review_due IS NULL OR i.review_due <= ?)
            """
        var binds: [Any?] = [ISO8601.string()]
        if let source {
            filter += " AND i.source_id = ?"
            binds.append(source.id)
        }
        binds.append(limit)
        return queryItems(filter + " ORDER BY i.review_due IS NULL, i.review_due, i.id LIMIT ?", binds)
    }

    private func queryItems(_ tail: String, _ binds: [Any?] = []) -> [Item] {
        guard let db else { return [] }
        // Soft-deleted rows stay in the table so a browser resend cannot bring
        // them back; every read has to leave them out.
        let clause = tail.hasPrefix("WHERE")
            ? "WHERE i.removed_at IS NULL AND " + tail.dropFirst("WHERE ".count)
            : "WHERE i.removed_at IS NULL " + tail
        let sql = "SELECT \(Self.itemColumns) FROM item i JOIN source s ON s.id = i.source_id \(clause)"
        return (try? db.query(sql, binds, Self.item)) ?? []
    }

    private static func item(_ r: Database.Row) -> Item {
        Item(
            id: r.int(0),
            sourceID: r.int(1),
            sourceKind: SourceKind(rawValue: r.string(2)) ?? .show,
            sourceTitle: r.string(3),
            sourceURL: r.string(4),
            kind: ItemKind(rawValue: r.string(5)) ?? .word,
            text: r.string(6),
            translation: r.string(7),
            context: r.string(8),
            contextTranslation: r.string(9),
            alternatives: r.string(14).split(separator: "\n").map(String.init),
            register: r.string(15),
            usageNote: r.string(16),
            position: r.double(10),
            starred: r.bool(11),
            status: ItemStatus(rawValue: r.string(12)) ?? .learning,
            createdAt: r.date(13))
    }

    // MARK: - Changes

    func toggleStar(_ item: Item) {
        write("UPDATE item SET starred = NOT starred WHERE id = ?", [item.id])
    }

    func setLearned(_ item: Item, _ learned: Bool) {
        write("UPDATE item SET status = ?, review_streak = 0, review_due = NULL WHERE id = ?",
              [learned ? ItemStatus.learned.rawValue : ItemStatus.learning.rawValue, item.id])
    }

    /// A meaning you typed in, perhaps what the other person told you.
    func setMeaning(_ item: Item, _ meaning: String) {
        write("UPDATE item SET translation = ? WHERE id = ?", [meaning, item.id])
    }

    /// The sentence kept with a word, trimmed or corrected by you.
    func setContext(_ item: Item, _ context: String) {
        write("UPDATE item SET context = ? WHERE id = ?", [context, item.id])
    }

    /// What a translator came back with. Replaces the meaning; keeps an
    /// existing sentence translation if this one has none.
    /// Writes a translation. `byModel` is false for Apple's translator, which
    /// has no alternatives or notes to give, so the model's earlier ones stay.
    func applyTranslation(
        _ meaning: String, sentence: String, alternatives: [String],
        register: String, note: String, byModel: Bool, to item: Item
    ) {
        write("""
            UPDATE item SET translation = ?,
                context_translation = COALESCE(NULLIF(?, ''), context_translation),
                alternatives = CASE WHEN ? THEN ? ELSE alternatives END,
                register = CASE WHEN ? THEN ? ELSE register END,
                usage_note = CASE WHEN ? THEN ? ELSE usage_note END,
                enriched_at = CASE WHEN ? THEN ? ELSE enriched_at END
            WHERE id = ?
            """, [meaning, sentence,
                  byModel, alternatives.joined(separator: "\n"),
                  byModel, register,
                  byModel, note,
                  byModel, ISO8601.string(),
                  item.id])
    }

    /// Translated words the model has not looked at yet: from the browser,
    /// which brings its own translation, or from before usage notes existed.
    func unenrichedItems(in scope: Scope = .all) -> [Item] {
        let waiting = "WHERE i.translation != '' AND i.enriched_at IS NULL"
        switch scope {
        case .all:
            return queryItems("\(waiting) ORDER BY i.created_at DESC")
        case .kind(let kind):
            return queryItems("\(waiting) AND s.kind = ? ORDER BY i.created_at DESC", [kind.rawValue])
        case .source(let source):
            return queryItems("\(waiting) AND i.source_id = ? ORDER BY i.created_at DESC", [source.id])
        }
    }

    /// Only the name shown here; an empty name goes back to the original.
    func renameSource(_ source: Source, to title: String) {
        write("UPDATE source SET display_title = ? WHERE id = ?",
              [title.trimmingCharacters(in: .whitespacesAndNewlines), source.id])
    }

    /// A whole episode, conversation or book: every word saved from it.
    func removeSource(_ source: Source) {
        write("UPDATE item SET removed_at = ? WHERE source_id = ? AND removed_at IS NULL",
              [ISO8601.string(), source.id])
    }

    func remove(_ item: Item) {
        write("UPDATE item SET removed_at = ? WHERE id = ?", [ISO8601.string(), item.id])
    }

    /// Adds a word you typed in. Saving one you deleted earlier brings it back.
    func addOwnWord(_ text: String, translation: String, context: String) {
        guard let db else { return }
        let now = ISO8601.string()
        do {
            try db.exec("BEGIN IMMEDIATE;")
            try db.run("""
                INSERT INTO source (kind, title, site, url, created_at)
                VALUES ('own', 'My words', '', 'own', ?)
                ON CONFLICT(kind, url, title) DO NOTHING
                """, [now])
            try db.run("""
                INSERT INTO item (source_id, kind, text, translation, context, created_at)
                SELECT id, ?, ?, ?, ?, ? FROM source WHERE kind = 'own' AND url = 'own'
                ON CONFLICT(source_id, kind, text) DO UPDATE SET
                    translation = COALESCE(NULLIF(excluded.translation, ''), item.translation),
                    context = COALESCE(NULLIF(excluded.context, ''), item.context),
                    removed_at = NULL
                """, [text.contains(" ") ? "phrase" : "word", text, translation, context, now])
            try db.exec("COMMIT;")
        } catch {
            try? db.exec("ROLLBACK;")
        }
        reload()
    }

    /// Three right answers in a row, spaced out, and a word counts as learned.
    /// A wrong answer starts it over and makes it due again straight away.
    func recordReview(_ item: Item, correct: Bool) {
        guard let db else { return }
        let now = Date()
        let streak = correct
            ? ((try? db.query("SELECT review_streak FROM item WHERE id = ?", [item.id]) { Int($0.int(0)) })?.first ?? 0) + 1
            : 0
        let learned = streak >= Self.streakToLearn
        let due = now.addingTimeInterval(correct ? Self.spacing(after: streak) : 0)

        do {
            try db.exec("BEGIN IMMEDIATE;")
            try db.run("INSERT INTO review (item_id, correct, at) VALUES (?, ?, ?)",
                       [item.id, correct, ISO8601.string(now)])
            try db.run("UPDATE item SET review_streak = ?, review_due = ?, status = ? WHERE id = ?",
                       [streak, ISO8601.string(due),
                        (learned ? ItemStatus.learned : .learning).rawValue, item.id])
            try db.exec("COMMIT;")
        } catch {
            try? db.exec("ROLLBACK;")
        }
        reload()
    }

    static let streakToLearn = 3

    private static func spacing(after streak: Int) -> TimeInterval {
        let day: TimeInterval = 86_400
        return streak <= 1 ? day : 3 * day
    }

    // MARK: - Chats

    /// Every conversation with the model, most recently active first.
    func chats() -> [ChatSummary] {
        guard let db else { return [] }
        return (try? db.query("""
            SELECT c.id, c.item_id, c.title, c.updated_at, COUNT(m.id)
            FROM chat c LEFT JOIN chat_message m ON m.chat_id = c.id
            GROUP BY c.id
            HAVING COUNT(m.id) > 0
            ORDER BY c.updated_at DESC
            """) { r in
            ChatSummary(id: r.int(0), itemID: r.isNull(1) ? nil : r.int(1), title: r.string(2),
                        updatedAt: r.date(3), messageCount: Int(r.int(4)))
        }) ?? []
    }

    /// The latest conversation about a word, so asking again picks it up.
    func chatID(for item: Item) -> Int64? {
        try? db?.query("SELECT id FROM chat WHERE item_id = ? ORDER BY updated_at DESC LIMIT 1",
                       [item.id]) { $0.int(0) }.first
    }

    func createChat(about item: Item?, title: String) -> Int64? {
        let now = ISO8601.string()
        return try? db?.run(
            "INSERT INTO chat (item_id, title, created_at, updated_at) VALUES (?, ?, ?, ?)",
            [item?.id, title, now, now])
    }

    func messages(in chatID: Int64) -> [ChatMessage] {
        (try? db?.query("SELECT id, role, content FROM chat_message WHERE chat_id = ? ORDER BY id",
                        [chatID]) { r in
            ChatMessage(id: r.int(0), role: ChatMessage.Role(rawValue: r.string(1)) ?? .user,
                        content: r.string(2))
        }) ?? []
    }

    @discardableResult
    func addMessage(_ role: ChatMessage.Role, _ content: String, to chatID: Int64) -> ChatMessage? {
        let now = ISO8601.string()
        guard let id = try? db?.run(
            "INSERT INTO chat_message (chat_id, role, content, at) VALUES (?, ?, ?, ?)",
            [chatID, role.rawValue, content, now]) else { return nil }
        _ = try? db?.run("UPDATE chat SET updated_at = ? WHERE id = ?", [now, chatID])
        chatsVersion += 1
        return ChatMessage(id: id, role: role, content: content)
    }

    func item(id: Int64) -> Item? {
        queryItems("WHERE i.id = ?", [id]).first
    }

    func deleteChat(_ chatID: Int64) {
        _ = try? db?.run("DELETE FROM chat WHERE id = ?", [chatID])
        chatsVersion += 1
    }

    private func write(_ sql: String, _ binds: [Any?]) {
        _ = try? db?.run(sql, binds)
        reload()
    }

    // MARK: - Loading

    func reloadIfChanged() {
        guard let db else { return }
        let next = (try? db.query("""
            SELECT COUNT(*), COALESCE(MAX(id), 0), COALESCE(SUM(starred), 0),
                   COALESCE(SUM(status = 'learned'), 0), COALESCE(SUM(removed_at IS NOT NULL), 0),
                   COALESCE(SUM(translation = ''), 0)
            FROM item
            """) { r in (Int32(0)..<6).map { "\(r.int($0))" }.joined(separator: ":") })?.first ?? ""
        guard next != fingerprint else { return }
        fingerprint = next
        reload()
    }

    func reload() {
        guard let db else { return }
        do {
            sources = try db.query("""
                SELECT s.id, s.kind, COALESCE(NULLIF(s.display_title, ''), s.title), s.site, s.url, s.created_at,
                       SUM(i.kind = 'word'), SUM(i.kind = 'phrase'),
                       MAX(i.created_at), SUM(i.status = 'learned'), s.display_title != ''
                FROM source s
                JOIN item i ON i.source_id = s.id AND i.removed_at IS NULL
                GROUP BY s.id
                ORDER BY 9 DESC
                """) { r in
                Source(
                    id: r.int(0),
                    kind: SourceKind(rawValue: r.string(1)) ?? .show,
                    title: r.string(2),
                    site: r.string(3),
                    url: r.string(4),
                    createdAt: r.date(5),
                    wordCount: Int(r.int(6)),
                    phraseCount: Int(r.int(7)),
                    lastSavedAt: r.date(8),
                    learnedCount: Int(r.int(9)),
                    renamed: r.int(10) != 0)
            }
            stats = try readStats(db)
            loadError = nil
        } catch {
            loadError = "\(error)"
        }
    }

    private func readStats(_ db: Database) throws -> Stats {
        let startOfDay = ISO8601.string(Calendar.current.startOfDay(for: Date()))
        var stats = try db.query("""
            SELECT COALESCE(SUM(status = 'learning'), 0),
                   COALESCE(SUM(status = 'learned'), 0),
                   COALESCE(SUM(created_at >= ?), 0),
                   COALESCE(SUM(translation = ''), 0),
                   COALESCE(SUM(status = 'learning' AND translation != ''
                                AND (review_due IS NULL OR review_due <= ?)), 0)
            FROM item WHERE removed_at IS NULL
            """, [startOfDay, ISO8601.string()]) { r in
            Stats(learning: Int(r.int(0)), learned: Int(r.int(1)), savedToday: Int(r.int(2)),
                  untranslated: Int(r.int(3)), due: Int(r.int(4)))
        }.first ?? Stats()

        let reviewDays = try db.query(
            "SELECT at FROM review WHERE at >= ? ORDER BY at DESC",
            [ISO8601.string(Date().addingTimeInterval(-90 * 86_400))]
        ) { Calendar.current.startOfDay(for: $0.date(0)) }

        stats.reviewedToday = reviewDays.filter { Calendar.current.isDateInToday($0) }.count
        stats.streak = Self.streak(days: Set(reviewDays))
        return stats
    }

    /// Counts back from today; a streak survives until the end of the day
    /// after its last review, so opening the app in the morning does not show
    /// it already broken.
    private static func streak(days: Set<Date>) -> Int {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: Date())
        if !days.contains(day) {
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        var count = 0
        while days.contains(day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }
}
