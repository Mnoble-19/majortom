import CallCore
import Foundation
import Observation

/// An in-person conversation. Much smaller than the Mac's `Session`: one mic,
/// one recognizer, no database, no translation.
///
/// There is only one audio track here, so unlike on a call there is no free
/// speaker labelling — everything in the room arrives on the same microphone.
@MainActor
@Observable
final class PhoneSession {
    private(set) var lines: [Line] = []
    private(set) var volatile = ""
    private(set) var isRunning = false
    private(set) var error: String?
    private(set) var modelState: ModelState = .unknown

    var person = ""
    var localeIdentifier = "de-DE"

    private(set) var sessionID = UUID().uuidString
    private(set) var startedAt = Date()

    private var transcriber: Transcriber?
    private var mic: MicSource?
    private var pump: Task<Void, Never>?

    enum ModelState: Equatable {
        case unknown
        case downloading
        case ready
        case unsupported(String)
    }

    /// The German model is a download on first use, and on a phone that is
    /// worth saying out loud rather than looking frozen.
    func prepareModel() async {
        guard modelState != .ready else { return }
        modelState = .downloading
        do {
            try await Transcriber.ensureModel(locale: Locale(identifier: localeIdentifier))
            modelState = .ready
        } catch {
            modelState = .unsupported("\(error)")
        }
    }

    func start() async {
        guard !isRunning else { return }
        error = nil
        guard !person.trimmingCharacters(in: .whitespaces).isEmpty else {
            error = "Who are you talking to?"
            return
        }
        await prepareModel()
        guard modelState == .ready else { return }

        sessionID = UUID().uuidString
        startedAt = Date()
        lines = []
        volatile = ""

        do {
            let transcriber = Transcriber(locale: Locale(identifier: localeIdentifier), speaker: .them)
            try await transcriber.start()
            let mic = MicSource()
            try mic.start { buffer, time in transcriber.append(buffer, at: time) }
            self.transcriber = transcriber
            self.mic = mic
            isRunning = true

            pump = Task { [weak self] in
                for await event in transcriber.events {
                    guard let self else { return }
                    switch event {
                    case .line(let line):
                        self.lines.append(line)
                        self.volatile = ""
                    case .volatile(_, let text):
                        self.volatile = text
                    }
                }
            }
        } catch {
            self.error = "\(error)"
        }
    }

    func stop() async {
        pump?.cancel()
        pump = nil
        mic?.stop()
        try? await transcriber?.finish()
        mic = nil
        transcriber = nil
        isRunning = false
        // Same rule as the Mac: the transcript is not kept anywhere.
        lines = []
        volatile = ""
    }
}
