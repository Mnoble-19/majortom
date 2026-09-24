import CallCore
import Foundation
import Observation

/// A word you clicked during this session.
///
/// It carries no translation. Translating is the library app's job — words are
/// saved blank here and filled in there, which is the same path the phone's
/// words take and means a model that is not running costs a translation rather
/// than a word.
struct SavedWord: Identifiable, Equatable {
    let id = UUID()
    /// Editable, because the recognizer sometimes mishears the very word you
    /// were reaching for and a wrong word in the library is worse than none.
    var word: String
    var sentence: String
    var position: TimeInterval
}

/// Bridges `Session` — which runs on audio threads — to the UI on the main
/// actor. Everything the views read lives here; nothing here touches audio.
@MainActor
@Observable
final class SessionModel {
    private(set) var lines: [Line] = []
    private(set) var volatile: [Speaker: String] = [:]
    private(set) var saved: [SavedWord] = []
    private(set) var isRunning = false
    private(set) var startedAt: Date?
    private(set) var error: String?
    private(set) var tappedApp: String?

    var person = Settings.lastPerson
    var localeIdentifier = "de-DE"

    private var session: Session?
    private var database: Database?
    private var pump: Task<Void, Never>?

    func start() async {
        guard !isRunning else { return }
        error = nil
        let name = person.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            error = "who are you talking to?"
            return
        }

        do {
            let database = try Database()
            self.database = database
            let session = Session(
                person: name,
                locale: Locale(identifier: localeIdentifier),
                database: database)
            try await session.start(their: .whicheverAppIsPlaying)
            self.session = session

            Settings.lastPerson = name
            Settings.setLocale(localeIdentifier, forPerson: name)
            tappedApp = AudioProcesses.likelyCall().first?.name
            startedAt = Date()
            isRunning = true
            lines = []
            volatile = [:]
            saved = []

            pump = Task { [weak self] in
                for await event in session.events {
                    guard let self else { return }
                    switch event {
                    case .line(let line):
                        self.lines.append(line)
                        self.volatile[line.speaker] = ""
                    case .volatile(let speaker, let text):
                        self.volatile[speaker] = text
                    }
                }
            }
        } catch {
            self.error = "\(error)"
            session = nil
        }
    }

    func end() async {
        pump?.cancel()
        pump = nil
        await session?.end()
        session = nil
        isRunning = false
        startedAt = nil
        tappedApp = nil
        // The transcript is deliberately not kept — only the words above.
        lines = []
        volatile = [:]
    }

    /// Saves straight away, with no translation. The library app fills those in.
    func save(word rawWord: String, from line: Line) {
        let word = rawWord.trimmingCharacters(in: CharacterSet.punctuationCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, let session else { return }
        guard !saved.contains(where: { $0.word.caseInsensitiveCompare(word) == .orderedSame }) else { return }

        let sentence = line.sentence(containing: word)
        try? session.save(word: word, from: line)
        saved.append(SavedWord(word: word, sentence: sentence, position: line.start))
    }

    /// Rewrites a word after you correct what the recognizer heard.
    func recorrect(_ id: SavedWord.ID, to newWord: String) {
        guard let index = saved.firstIndex(where: { $0.id == id }), let session else { return }
        let word = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, word != saved[index].word else { return }

        let line = Line(speaker: .them, text: saved[index].sentence, start: saved[index].position)
        try? session.correct(saved[index].word, to: word, from: line)
        saved[index].word = word
    }
}
