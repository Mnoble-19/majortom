import Foundation
import SwiftUI

/// Reads the shared database and republishes it to the UI. The host process
/// writes behind our back, so we re-check cheaply on a timer and on focus.
@MainActor
final class Store: ObservableObject {
    @Published private(set) var sources: [Source] = []
    @Published private(set) var loadError: String?

    private var db: Database?
    private var fingerprint: String = ""
    private var timer: Timer?

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

    func sources(of kind: SourceKind) -> [Source] {
        sources.filter { $0.kind == kind }
    }

    func reloadIfChanged() {
        guard let db else { return }
        let next = (try? db.query(
            "SELECT COUNT(*), COALESCE(MAX(id), 0), COALESCE(SUM(starred), 0) FROM item"
        ) { "\($0.int(0)):\($0.int(1)):\($0.int(2))" })?.first ?? ""
        guard next != fingerprint else { return }
        fingerprint = next
        reload()
    }

    func reload() {
        guard let db else { return }
        do {
            sources = try db.query("""
                SELECT s.id, s.kind, s.title, s.site, s.url, s.created_at,
                       COALESCE(SUM(i.kind = 'word'), 0),
                       COALESCE(SUM(i.kind = 'phrase'), 0),
                       COALESCE(MAX(i.created_at), s.created_at)
                FROM source s
                LEFT JOIN item i ON i.source_id = s.id
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
                    lastSavedAt: r.date(8)
                )
            }
            loadError = nil
        } catch {
            loadError = "\(error)"
        }
    }

    func items(for source: Source, kind: ItemKind) -> [Item] {
        guard let db else { return [] }
        return (try? db.query("""
            SELECT id, source_id, kind, text, translation, context,
                   context_translation, position, starred, created_at
            FROM item WHERE source_id = ? AND kind = ?
            ORDER BY position, id
            """, [source.id, kind.rawValue]) { r in
            Item(
                id: r.int(0),
                sourceID: r.int(1),
                kind: ItemKind(rawValue: r.string(2)) ?? .word,
                text: r.string(3),
                translation: r.string(4),
                context: r.string(5),
                contextTranslation: r.string(6),
                position: r.double(7),
                starred: r.bool(8),
                createdAt: r.date(9)
            )
        }) ?? []
    }

    /// Recently saved items across every show, for the launch screen list.
    func recentItems(limit: Int = 40) -> [(item: Item, sourceTitle: String)] {
        guard let db else { return [] }
        return (try? db.query("""
            SELECT i.id, i.source_id, i.kind, i.text, i.translation, i.context,
                   i.context_translation, i.position, i.starred, i.created_at, s.title
            FROM item i JOIN source s ON s.id = i.source_id
            ORDER BY i.created_at DESC, i.id DESC LIMIT ?
            """, [limit]) { r in
            (
                Item(
                    id: r.int(0), sourceID: r.int(1),
                    kind: ItemKind(rawValue: r.string(2)) ?? .word,
                    text: r.string(3), translation: r.string(4), context: r.string(5),
                    contextTranslation: r.string(6), position: r.double(7),
                    starred: r.bool(8), createdAt: r.date(9)
                ),
                r.string(10)
            )
        }) ?? []
    }

    func toggleStar(_ item: Item) {
        _ = try? db?.run("UPDATE item SET starred = NOT starred WHERE id = ?", [item.id])
        reload()
        objectWillChange.send()
    }
}
