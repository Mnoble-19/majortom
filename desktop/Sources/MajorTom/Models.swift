import Foundation

/// Where saved material came from. Shows exist today; calls and books are the
/// same shape, so those projects write into these tables without a migration.
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

    var icon: String {
        switch name {
        case "YouTube", "Vimeo", "Dailymotion": return "play.rectangle.fill"
        case "Netflix", "Disney+": return "film.fill"
        case "Twitch": return "dot.radiowaves.left.and.right"
        default: return "antenna.radiowaves.left.and.right"
        }
    }
}

struct Item: Identifiable, Hashable {
    var id: Int64
    var sourceID: Int64
    var kind: ItemKind
    var text: String
    var translation: String
    var context: String
    var contextTranslation: String
    /// Playback seconds for video, offset for calls, locator for books.
    var position: Double
    var starred: Bool
    var status: ItemStatus
    var createdAt: Date
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
