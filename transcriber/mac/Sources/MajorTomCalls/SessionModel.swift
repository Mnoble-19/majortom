import CallCore
import Foundation
import Observation

/// A word you clicked, and how far its translation has got.
struct SavedWord: Identifiable, Equatable {
    let id = UUID()
    /// Editable, because the recognizer sometimes mishears the very word you
    /// were reaching for and a wrong word in the library is worse than none.
    var word: String
    var sentence: String
    var position: TimeInterval
    var gloss: Gloss?
    var state: State = .translating

    enum State: Equatable {
        case translating
        case done
        case failed(String)
    }
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

    /// Apple's translator is the instant floor; it needs its language pack
    /// installed, which is a System Settings step we cannot do for them.
    private(set) var appleTranslationReady = false

    func refreshTranslationAvailability() async {
        appleTranslationReady = await AppleTranslator().isAvailable()
    }

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

    /// Saves straight away with no translation, then fills it in. A dead model
    /// or a slow one costs you a translation, never the word.
    func save(word rawWord: String, from line: Line) {
        let word = rawWord.trimmingCharacters(in: CharacterSet.punctuationCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, let session else { return }
        guard !saved.contains(where: { $0.word.caseInsensitiveCompare(word) == .orderedSame }) else { return }

        let sentence = line.sentence(containing: word)
        var entry = SavedWord(word: word, sentence: sentence, position: line.start)
        try? session.save(word: word, from: line)
        saved.append(entry)
        entry.state = .translating

        translate(entry.id, word: word, sentence: sentence, context: contextLines(around: line))
    }

    /// Re-runs a word after you correct what the recognizer heard.
    func recorrect(_ id: SavedWord.ID, to newWord: String) {
        guard let index = saved.firstIndex(where: { $0.id == id }), let session else { return }
        let word = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, word != saved[index].word else { return }

        saved[index].word = word
        saved[index].gloss = nil
        saved[index].state = .translating
        let sentence = saved[index].sentence
        let line = Line(speaker: .them, text: sentence, start: saved[index].position)
        try? session.save(word: word, from: line)
        translate(id, word: word, sentence: sentence, context: [])
    }

    private func translate(_ id: SavedWord.ID, word: String, sentence: String, context: [String]) {
        Task { [weak self] in
            let translator = Translator()
            var received = false
            for await gloss in translator.glosses(word: word, sentence: sentence, context: context) {
                received = true
                guard let self else { return }
                self.apply(gloss, to: id)
            }
            guard let self else { return }
            if !received { self.markFailed(id, "no translator available") }
        }
    }

    private func apply(_ gloss: Gloss, to id: SavedWord.ID) {
        guard let index = saved.firstIndex(where: { $0.id == id }) else { return }
        saved[index].gloss = gloss
        // Apple's answer is a placeholder until the model's arrives; the model's
        // is final.
        saved[index].state = gloss.origin == .model ? .done : .translating

        if let database, let sourceID = session?.databaseSourceID {
            try? database.upsertItem(
                sourceID: sourceID,
                text: saved[index].word,
                translation: gloss.meaning,
                context: saved[index].sentence,
                contextTranslation: gloss.sentence,
                position: saved[index].position)
        }
    }

    private func markFailed(_ id: SavedWord.ID, _ reason: String) {
        guard let index = saved.firstIndex(where: { $0.id == id }) else { return }
        if saved[index].gloss == nil { saved[index].state = .failed(reason) }
    }

    /// The two lines before and one after, which is what lets the model tell
    /// one sense of a word from another.
    private func contextLines(around line: Line) -> [String] {
        guard let index = lines.firstIndex(of: line) else { return [] }
        let lower = max(0, index - 2)
        let upper = min(lines.count - 1, index + 1)
        return lines[lower...upper].map { "\($0.speaker == .me ? "me" : person): \($0.text)" }
    }
}
