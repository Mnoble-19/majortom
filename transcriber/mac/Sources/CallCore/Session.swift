import AVFoundation
import Foundation

/// One call. Runs a recognizer on each audio track, keeps the transcript in
/// memory only, and writes the words you pick to the database.
///
/// The transcript is deliberately not persisted anywhere — not to disk, not to
/// the database. `end()` drops it. Only saved words outlive the session.
public final class Session: @unchecked Sendable {
    public let person: String
    public let sessionID = UUID().uuidString
    public let startedAt = Date()

    private let locale: Locale
    private let database: Database
    private var sourceID: Int64?

    private var theirs: Transcriber?
    private var mine: Transcriber?
    #if os(macOS)
    private var tap: ProcessTapSource?
    #endif
    private var mic: MicSource?
    private var relays: [Task<Void, Never>] = []

    private let lock = NSLock()
    private var lines: [Line] = []
    private var volatileBySpeaker: [Speaker: String] = [:]

    /// Live transcript updates for the UI. Lines are append-only; volatile text
    /// is replaced as the recognizer revises it.
    public let events: AsyncStream<TranscriptEvent>
    private let emit: AsyncStream<TranscriptEvent>.Continuation

    public init(person: String, locale: Locale = Locale(identifier: "de-DE"), database: Database) {
        self.person = person
        self.locale = locale
        self.database = database
        let (stream, continuation) = AsyncStream.makeStream(of: TranscriptEvent.self)
        events = stream
        emit = continuation
    }

    public var transcript: [Line] {
        lock.withLock { lines }
    }

    /// The `source` row this session writes to, so callers can update an item's
    /// translation after the fact without re-deriving it.
    public var databaseSourceID: Int64? { sourceID }

    public func volatileText(for speaker: Speaker) -> String {
        lock.withLock { volatileBySpeaker[speaker] ?? "" }
    }

    /// Where the other person's voice comes from.
    public enum TheirAudio {
        /// Whatever app is playing audio when the session starts. The normal
        /// case: nothing to pick, and it does not matter whether the call is on
        /// Signal, WhatsApp or anything else.
        case whicheverAppIsPlaying
        /// A named app, for when several are making noise at once.
        case app(String)
        /// Mic only — in person, or a phone on speaker.
        case none
    }

    public func start(their source: TheirAudio = .whicheverAppIsPlaying) async throws {
        try await Transcriber.ensureModel(locale: locale)

        let title = Session.title(person: person, at: startedAt)
        sourceID = try database.upsertSource(
            title: title, person: person, sessionID: sessionID, origin: "mac", createdAt: startedAt)

        #if os(macOS)
        let callProcesses: [AudioProcess]
        switch source {
        case .whicheverAppIsPlaying: callProcesses = AudioProcesses.likelyCall()
        case .app(let name): callProcesses = AudioProcesses.group(name)
        case .none: callProcesses = []
        }

        if !callProcesses.isEmpty {
            let theirs = Transcriber(locale: locale, speaker: .them)
            try await theirs.start()
            let tap = try ProcessTapSource(processes: callProcesses)
            try tap.start { buffer, _ in theirs.append(buffer) }
            self.theirs = theirs
            self.tap = tap
            relay(theirs)
        }
        #endif

        let mine = Transcriber(locale: locale, speaker: .me)
        try await mine.start()
        let mic = MicSource()
        try mic.start { buffer, time in mine.append(buffer, at: time) }
        self.mine = mine
        self.mic = mic
        relay(mine)
    }

    /// Both recognizers feed one merged stream, tagged by track.
    private func relay(_ transcriber: Transcriber) {
        let task = Task { [weak self] in
            for await event in transcriber.events {
                guard let self else { return }
                switch event {
                case .line(let line):
                    self.lock.withLock {
                        self.lines.append(line)
                        self.volatileBySpeaker[line.speaker] = ""
                    }
                case .volatile(let speaker, let text):
                    self.lock.withLock { self.volatileBySpeaker[speaker] = text }
                }
                self.emit.yield(event)
            }
        }
        relays.append(task)
    }

    /// Saves one word with the sentence it came from. `translation` may be
    /// empty — the fill-in pass will pick it up later.
    public func save(
        word: String,
        from line: Line,
        translation: String = "",
        contextTranslation: String = ""
    ) throws {
        guard let sourceID else { return }
        let word = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }

        try database.upsertItem(
            sourceID: sourceID,
            text: word,
            translation: translation,
            context: line.sentence(containing: word),
            contextTranslation: contextTranslation,
            position: line.start
        )
    }

    /// Stops capture and drops the transcript. Saved words are already in the
    /// database by this point; nothing here writes anything.
    public func end() async {
        #if os(macOS)
        tap?.stop()
        #endif
        mic?.stop()
        try? await theirs?.finish()
        try? await mine?.finish()
        for relay in relays { relay.cancel() }
        relays.removeAll()
        emit.finish()

        lock.withLock {
            lines.removeAll()
            volatileBySpeaker.removeAll()
        }
        theirs = nil
        mine = nil
        mic = nil
        #if os(macOS)
        tap = nil
        #endif
    }

    static func title(person: String, at date: Date) -> String {
        let day = date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        return "Call with \(person) — \(day)"
    }
}
