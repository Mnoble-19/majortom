import CallCore
import Foundation

/// The phone's entire storage: words picked in person, waiting to be synced.
///
/// Deliberately a JSON file and not SQLite. The library lives on the Mac — this
/// is a holding pen for a handful of words between a conversation and the next
/// time the two devices are near each other.
@MainActor
@Observable
final class PendingWords {
    private(set) var sessions: [StoredSession] = []

    private let fileURL: URL = {
        let directory = URL.documentsDirectory
        return directory.appending(path: "pending.json")
    }()

    init() { load() }

    var totalWords: Int { sessions.reduce(0) { $0 + $1.words.count } }

    func add(_ word: SyncPayload.Word, to sessionID: String, person: String, startedAt: Date) {
        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            // Same word twice in one conversation is one word.
            guard !sessions[index].words.contains(where: {
                $0.text.caseInsensitiveCompare(word.text) == .orderedSame
            }) else { return }
            sessions[index].words.append(word)
        } else {
            sessions.append(StoredSession(
                id: sessionID, person: person, startedAt: startedAt, words: [word]))
        }
        save()
    }

    func remove(_ text: String, from sessionID: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].words.removeAll { $0.text == text }
        if sessions[index].words.isEmpty { sessions.remove(at: index) }
        save()
    }

    func replace(_ old: String, with new: String, in sessionID: String) {
        guard let session = sessions.firstIndex(where: { $0.id == sessionID }),
              let word = sessions[session].words.firstIndex(where: { $0.text == old })
        else { return }
        sessions[session].words[word].text = new
        save()
    }

    /// Only drops what the Mac actually acknowledged, so a partial sync does
    /// not quietly lose the rest.
    func clearSynced(_ sessionID: String) {
        sessions.removeAll { $0.id == sessionID }
        save()
    }

    func payloads() -> [SyncPayload] {
        sessions.map {
            SyncPayload(sessionID: $0.id, person: $0.person,
                        startedAt: $0.startedAt, words: $0.words)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? SyncProtocol.decoder.decode([StoredSession].self, from: data)
        else { return }
        sessions = decoded
    }

    private func save() {
        guard let data = try? SyncProtocol.encoder.encode(sessions) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

struct StoredSession: Codable, Identifiable, Sendable {
    var id: String
    var person: String
    var startedAt: Date
    var words: [SyncPayload.Word]
}
