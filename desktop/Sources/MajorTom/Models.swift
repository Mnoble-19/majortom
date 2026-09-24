import Foundation

/// Where saved material came from. Shows, calls and books share one shape, so
/// every capture tool writes into the same tables.
enum SourceKind: String, Codable, CaseIterable {
    case show, call, book
}

enum ItemKind: String, Codable, CaseIterable {
    case word, phrase
}

/// Nothing is ever deleted by learning it — `learned` items stay in the
/// library, just out of the way.
enum ItemStatus: String, Codable, CaseIterable {
    case learning, learned

    var label: String {
        switch self {
        case .learning: return "To learn"
        case .learned: return "Learned"
        }
    }
}

struct Source: Identifiable, Hashable {
    var id: Int64
    var kind: SourceKind
    var title: String
    var site: String
    var url: String
    var createdAt: Date
    var wordCount: Int
    var phraseCount: Int
    var lastSavedAt: Date
    var learnedCount: Int

    var itemCount: Int { wordCount + phraseCount }
    var progress: Double { itemCount == 0 ? 0 : Double(learnedCount) / Double(itemCount) }
}

/// Sources grouped by the site they came from. Derived, never stored: the
/// grouping key is `source.site`.
struct Platform: Identifiable, Hashable {
    /// The raw host, e.g. "ardmediathek.de".
    var id: String
    var showCount: Int
    var wordCount: Int
    var lastSavedAt: Date

    var name: String { Platform.displayName(for: id) }

    static func displayName(for site: String) -> String {
        let host = site.lowercased()
            .replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
        guard !host.isEmpty else { return "Unknown" }

        let known = [
            "youtube": "YouTube", "ardmediathek": "ARD", "ard.de": "ARD",
            "zdf": "ZDF", "netflix": "Netflix", "disneyplus": "Disney+",
            "arte": "ARTE", "vimeo": "Vimeo", "twitch": "Twitch",
            "dailymotion": "Dailymotion", "3sat": "3sat", "servustv": "ServusTV",
        ]
        if let hit = known.first(where: { host.contains($0.key) }) { return hit.value }

        let base = host.split(separator: ".").dropLast().last.map(String.init) ?? host
        return base.prefix(1).uppercased() + base.dropFirst()
    }
}

struct Item: Identifiable, Hashable {
    var id: Int64
    var sourceID: Int64
    var sourceKind: SourceKind
    var sourceTitle: String
    var sourceURL: String
    var kind: ItemKind
    var text: String
    var translation: String
    var context: String
    var contextTranslation: String
    /// Playback seconds for video, offset for calls, page for books.
    var position: Double
    var starred: Bool
    var status: ItemStatus
    var createdAt: Date

    /// "23:14" into a show or call, "page 48" in a book. Rendering a page as a
    /// time would be quietly wrong, so the two never share a format.
    var positionLabel: String? {
        guard position > 0 else { return nil }
        if sourceKind == .book { return "page \(Int(position))" }
        let total = Int(position)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// The numbers the home screen is built from, read in one go.
struct Stats: Equatable {
    var learning = 0
    var learned = 0
    var savedToday = 0
    var untranslated = 0
    var due = 0
    var reviewedToday = 0
    /// Consecutive days, ending today or yesterday, with at least one review.
    var streak = 0
}

/// A `VocabEntry` as the extension serialises it over native messaging.
struct IncomingEntry: Codable {
    var word: String
    var translation: String?
    var context: String?
    var contextTranslation: String?
    var site: String?
    var title: String?
    var url: String?
    var time: Double?
    var createdAt: String?
    var starred: Bool?
}

/// A change the browser made itself. Reported explicitly because the sending
/// browser's vocabulary is not the whole library — several browsers feed it.
struct Mutation: Codable {
    /// "delete" or "star".
    var kind: String
    var word: String
    var url: String
    var starred: Bool?
}

struct SyncRequest: Codable {
    var type: String
    var entries: [IncomingEntry]?
    var mutations: [Mutation]?
}

struct SyncResponse: Codable {
    var ok: Bool
    var written: Int?
    var error: String?
}
