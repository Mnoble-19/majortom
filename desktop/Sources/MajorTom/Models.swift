import Foundation

/// Where saved material came from. Shows exist today; calls and books are the
/// same shape, so those projects write into these tables without a migration.
enum SourceKind: String, Codable, CaseIterable {
    case show, call, book
}

enum ItemKind: String, Codable, CaseIterable {
    case word, phrase
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

struct SyncRequest: Codable {
    var type: String
    var entries: [IncomingEntry]?
}

struct SyncResponse: Codable {
    var ok: Bool
    var written: Int?
    var error: String?
}
