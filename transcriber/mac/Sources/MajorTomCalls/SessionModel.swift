import CallCore
import Foundation
import Observation

/// A word or phrase you clicked during this session.
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
    private(set) var volatile = ""
    private(set) var saved: [SavedWord] = []
    private(set) var isRunning = false
    private(set) var startedAt: Date?
    private(set) var error: String?
    private(set) var tappedApp: String?
    /// The call that just ended, shown until the next one starts.
    private(set) var finished: Finished?

    struct Finished {
        let person: String
        let words: [SavedWord]
    }

    var person = Settings.lastPerson
    var localeIdentifier = Settings.locale(forPerson: Settings.lastPerson)

    private var session: Session?
    /// Set across the awaits in `start()`, so a second Return or menu click
    /// while the first is still starting does not open a second session.
    private var starting = false
    private var database: Database?
    private var pump: Task<Void, Never>?

    func start() async {
        guard !isRunning, !starting else { return }
        starting = true
        defer { starting = false }
        error = nil
        let name = person.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            error = "Who are you talking to?"
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
            volatile = ""
            saved = []
            finished = nil

            pump = Task { [weak self] in
                for await event in session.events {
                    guard let self else { return }
                    switch event {
                    case .line(let line):
                        self.lines.append(line)
                        self.volatile = ""
                    case .volatile(let text):
                        self.volatile = text
                    }
                }
            }
        } catch {
            self.error = "\(error)"
            session = nil
        }
    }

    func end() async {
        if !saved.isEmpty {
            finished = Finished(person: person, words: saved)
        }
        pump?.cancel()
        pump = nil
        await session?.end()
        session = nil
        isRunning = false
        startedAt = nil
        tappedApp = nil
        // The transcript is deliberately not kept — only the words above.
        lines = []
        volatile = ""
    }

    func startOver() {
        finished = nil
        saved = []
    }

    /// The word last clicked, where a phrase starts if the next click holds
    /// Shift. Cleared once the phrase is saved.
    private(set) var phraseStart: (line: Line.ID, index: Int, saved: SavedWord.ID?)?

    /// A plain click saves the word. A Shift-click on another word in the same
    /// line turns the last clicked word into the phrase running between them.
    func tap(_ index: Int, in line: Line, extending: Bool) {
        let tokens = line.text.split(separator: " ").map(String.init)
        guard tokens.indices.contains(index) else { return }

        if extending, let start = phraseStart, start.line == line.id, start.index != index {
            let phrase = Self.clean(tokens[min(start.index, index)...max(start.index, index)]
                .joined(separator: " "))
            if let id = start.saved, let i = saved.firstIndex(where: { $0.id == id }) {
                try? session?.correct(saved[i].word, to: phrase, from: line)
                saved[i].word = phrase
                saved[i].sentence = line.sentence(containing: phrase)
            } else {
                save(phrase, from: line)
            }
            phraseStart = nil
            return
        }
        phraseStart = (line.id, index, save(tokens[index], from: line))
    }

    /// Saves straight away, with no translation. The library app fills those in.
    @discardableResult
    private func save(_ raw: String, from line: Line) -> SavedWord.ID? {
        let text = Self.clean(raw)
        guard !text.isEmpty, let session else { return nil }
        guard !saved.contains(where: { $0.word.caseInsensitiveCompare(text) == .orderedSame }) else { return nil }

        try? session.save(word: text, from: line)
        let word = SavedWord(word: text, sentence: line.sentence(containing: text), position: line.start)
        saved.append(word)
        return word.id
    }

    /// Trims the punctuation a transcript leaves on the ends — "Ahnung," — but
    /// keeps what sits inside a phrase.
    private static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
    }

    /// Rewrites a word after you correct what the recognizer heard.
    func recorrect(_ id: SavedWord.ID, to newWord: String) {
        guard let index = saved.firstIndex(where: { $0.id == id }), let session else { return }
        let word = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, word != saved[index].word else { return }

        let line = Line(text: saved[index].sentence, start: saved[index].position)
        try? session.correct(saved[index].word, to: word, from: line)
        saved[index].word = word
    }
}
