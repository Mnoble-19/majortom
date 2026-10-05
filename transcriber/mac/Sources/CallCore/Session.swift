// Writes to the database and taps another app, both of which are the Mac's
// job. The phone runs its own, much smaller session.
#if os(macOS)
import AVFoundation
import Foundation

/// One call. Transcribes the other person's side — the audio of whichever app
/// the call is in — keeps the transcript in memory only, and writes the words
/// you pick to the database.
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

    private var transcriber: Transcriber?
    private var tap: ProcessTapSource?
    private var relay: Task<Void, Never>?

    private let lock = NSLock()
    private var lines: [Line] = []

    /// Live transcript updates for the UI. Lines are append-only; volatile text
    /// is replaced as the recognizer revises it.
    public let events: AsyncStream<TranscriptEvent>
    private let emit: AsyncStream<TranscriptEvent>.Continuation

    public enum Failure: Error, CustomStringConvertible {
        case nothingPlaying

        public var description: String {
            "No app is playing audio. Start the call first, then press Start."
        }
    }

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

    /// Where the other person's voice comes from.
    public enum TheirAudio {
        /// Whatever app is playing audio when the session starts. The normal
        /// case: nothing to pick, and it does not matter whether the call is on
        /// Signal, WhatsApp or anything else.
        case whicheverAppIsPlaying
        /// A named app, for when several are making noise at once.
        case app(String)
    }

    public func start(their source: TheirAudio = .whicheverAppIsPlaying) async throws {
        let processes: [AudioProcess]
        switch source {
        case .whicheverAppIsPlaying: processes = AudioProcesses.likelyCall()
        case .app(let name): processes = AudioProcesses.group(name)
        }
        Log.info("playing now: " + AudioProcesses.playing().map { "\($0.name) [\($0.bundleID)]" }
            .joined(separator: ", "))
        guard !processes.isEmpty else {
            Log.warn("start: nothing is playing audio")
            throw Failure.nothingPlaying
        }
        Log.info("start: tapping \(processes.count) process(es): "
            + processes.map { "\($0.name) [\($0.bundleID)]" }.joined(separator: ", "))

        try await Transcriber.ensureModel(locale: locale)
        sourceID = try database.upsertSource(
            title: Session.title(person: person, at: startedAt),
            person: person, sessionID: sessionID, origin: "mac", createdAt: startedAt)

        let transcriber = Transcriber(locale: locale)
        try await transcriber.start()
        let tap = try ProcessTapSource(processes: processes)
        try tap.start { buffer, _ in transcriber.append(buffer) }
        self.transcriber = transcriber
        self.tap = tap

        relay = Task { [weak self] in
            for await event in transcriber.events {
                guard let self else { return }
                if case .line(let line) = event {
                    self.lock.withLock { self.lines.append(line) }
                }
                self.emit.yield(event)
            }
        }
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

    /// Replaces a misheard word, so the wrong one does not stay in the library.
    public func correct(_ old: String, to new: String, from line: Line) throws {
        guard let sourceID else { return }
        try database.deleteItem(sourceID: sourceID, text: old)
        try save(word: new, from: line)
    }

    /// Stops capture and drops the transcript. Saved words are already in the
    /// database by this point; nothing here writes anything.
    public func end() async {
        Log.info("end: \(lock.withLock { lines.count }) line(s) heard")
        tap?.stop()
        try? await transcriber?.finish()
        relay?.cancel()
        emit.finish()
        lock.withLock { lines.removeAll() }
        transcriber = nil
        tap = nil
    }

    static func title(person: String, at date: Date) -> String {
        let day = date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        return "Call with \(person) — \(day)"
    }
}
#endif
