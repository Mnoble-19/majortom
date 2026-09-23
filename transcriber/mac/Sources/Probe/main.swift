import AVFoundation
import CallCore
import Foundation

// Smoke test for the capture and recognizer end of the pipeline — no UI and no
// database in the way. Audio comes from a file, the mic, or a tap on another
// app; all three go through the same `append` path the real session uses.
//
//   swift run Probe --list                 # what is playing, and everything tappable
//   swift run Probe --tap 60               # whatever is playing, for 60s
//   swift run Probe --tap Signal 60        # a named app instead
//   swift run Probe --file clip.aiff       # a file, paced at 1x
//   swift run Probe 30                     # the mic

setvbuf(stdout, nil, _IOLBF, 0)

/// Peak amplitude of whatever is flowing through a capture source.
final class Meter: @unchecked Sendable {
    private let lock = NSLock()
    private var windowPeak: Float = 0
    private(set) var overallPeak: Float = 0
    private var silentSeconds = 0

    func observe(_ buffer: AVAudioPCMBuffer) {
        var peak: Float = 0
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        if let data = buffer.floatChannelData {
            // Interleaved buffers expose one pointer holding every channel.
            let samples = buffer.format.isInterleaved ? frames * channels : frames
            for channel in 0..<(buffer.format.isInterleaved ? 1 : channels) {
                for frame in 0..<samples { peak = max(peak, abs(data[channel][frame])) }
            }
        }
        lock.withLock {
            windowPeak = max(windowPeak, peak)
            overallPeak = max(overallPeak, peak)
        }
    }

    func reportIfQuiet() {
        let peak = lock.withLock { let p = windowPeak; windowPeak = 0; return p }
        lock.withLock {
            if peak < 0.0001 { silentSeconds += 1 } else { silentSeconds = 0 }
            if silentSeconds == 5 {
                print("\u{1B}[2K\r  (5s of silence — the tap is running but that app is not making sound)")
            }
        }
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.first == "--locales" {
    let supported = await SpeechTranscriberLocales.supported
    let installed = await SpeechTranscriberLocales.installed
    print("installed: \(installed.sorted().joined(separator: ", "))")
    print("German variants supported: \(supported.filter { $0.hasPrefix("de") }.sorted().joined(separator: ", "))")
    print("all supported (\(supported.count)): \(supported.sorted().joined(separator: ", "))")
    exit(0)
}

if arguments.first == "--db" {
    // Exercises the write path without any audio: two saves of the same word
    // must update rather than duplicate, which is what the sync relies on.
    //
    // It refuses to run against the real library, because it writes rows — and
    // writing junk into the vocabulary you are actually learning from is worse
    // than an inconvenient extra step.
    guard ProcessInfo.processInfo.environment["MAJORTOM_DB"]?.isEmpty == false else {
        print("""
            refusing to run: this writes test rows, so point it somewhere scratch.

              MAJORTOM_DB=/tmp/probe.sqlite swift run Probe --db

            (unset, it would write to \(Database.defaultURL().path))
            """)
        exit(1)
    }
    let database = try Database()
    print("database: \(Database.defaultURL().path)")
    let sessionID = UUID().uuidString
    let sourceID = try database.upsertSource(title: "Call with Ana — 2026-09-23",
                                             person: "Ana", sessionID: sessionID)
    let line = Line(speaker: .them,
                    text: "Das war ziemlich beharrlich von ihm. Sie hat nicht nachgegeben.",
                    start: 142)

    try database.upsertItem(sourceID: sourceID, text: "beharrlich", translation: "",
                            context: line.sentence(containing: "beharrlich"), position: line.start)
    try database.upsertItem(sourceID: sourceID, text: "beharrlich", translation: "persistent",
                            context: line.sentence(containing: "beharrlich"), position: line.start)

    let pending = try database.untranslatedItems(sourceID: sourceID)
    print("source id \(sourceID), \(pending.count) item(s) still untranslated")
    print("context stored: \(line.sentence(containing: "beharrlich"))")
    exit(0)
}

if arguments.first == "--serve" {
    // The Mac end of the phone sync, on its own so the protocol can be tested
    // before there is a phone to test it with.
    guard ProcessInfo.processInfo.environment["MAJORTOM_DB"]?.isEmpty == false else {
        print("set MAJORTOM_DB to somewhere scratch first")
        exit(1)
    }
    let database = try Database()
    print("writing to \(Database.defaultURL().path)")

    var llm = LLMSettings.empty
    llm.endpoint = ProcessInfo.processInfo.environment["MT_ENDPOINT"] ?? llm.endpoint
    llm.model = (try? await ModelTranslator(settings: llm, apiKey: "").models().first) as? String ?? ""
    print(llm.model.isEmpty
        ? "no model reachable at \(llm.endpoint) — words will import untranslated"
        : "translating with \(llm.model)")
    let settings = llm

    let server = SyncServer(
        database: database,
        translator: { Translator(settings: settings, apiKey: "") }
    ) { report in
        print("  ← \(report.person): \(report.words) word(s), source \(report.sourceID)")
        print("    translating in the background…")
    }
    try server.start()
    try await Task.sleep(for: .milliseconds(300))
    print("listening on port \(server.port.map(String.init) ?? "?") as \(SyncProtocol.serviceType)")
    print("ctrl-c to stop")
    try await Task.sleep(for: .seconds(600))
    exit(0)
}

if arguments.first == "--send" {
    // Pretends to be the phone: one session, a few words, no translations.
    let host = arguments.dropFirst().first ?? "127.0.0.1"
    let payload = SyncPayload(
        sessionID: UUID().uuidString,
        person: arguments.dropFirst(2).first ?? "Ana",
        startedAt: Date(),
        words: [
            .init(text: "beharrlich",
                  sentence: "Das war ziemlich beharrlich von ihm.", position: 12),
            .init(text: "angezogen",
                  sentence: "Die Preise haben in letzter Zeit deutlich angezogen.", position: 48),
            .init(text: "aufgegeben",
                  sentence: "Er hat das Paket gestern bei der Post aufgegeben.", position: 95)
        ])
    print("sending \(payload.words.count) words to \(host)…")
    let result = try await SyncClient().send(payload, to: host, port: SyncProtocol.defaultPort)
    print("accepted: \(result.accepted)\(result.error.map { ", error: \($0)" } ?? "")")
    exit(0)
}

if arguments.first == "--translate" {
    // Both providers against a real endpoint, timed, so the latency and the
    // quality difference are visible rather than assumed.
    let endpoint = arguments.dropFirst().first ?? Settings.llm.endpoint
    let word = arguments.dropFirst(2).first ?? "abbringen"
    let sentence = arguments.dropFirst(3).first ?? "Sie hat sich nicht davon abbringen lassen."

    let apple = AppleTranslator()
    print("Apple translator installed for de→en: \(await apple.isAvailable())")
    let appleStart = Date()
    do {
        let gloss = try await apple.gloss(word: word, sentence: sentence)
        print(String(format: "  [%.2fs] %@ → %@", -appleStart.timeIntervalSinceNow,
                     gloss.dictionaryForm, gloss.meaning))
        print("         sentence: \(gloss.sentence)")
    } catch {
        print("  unavailable: \(error)")
    }

    var settings = Settings.llm
    settings.endpoint = endpoint
    let probe = ModelTranslator(settings: settings, apiKey: Settings.apiKey)
    print("\nendpoint \(endpoint)")
    let names = try await probe.models()
    print("models: \(names.joined(separator: ", "))")
    settings.model = names.first ?? ""

    for skip in [false, true] {
        settings.skipReasoning = skip
        let translator = ModelTranslator(settings: settings, apiKey: Settings.apiKey)
        let start = Date()
        do {
            let gloss = try await translator.gloss(word: word, sentence: sentence)
            print(String(format: "\n%@ (%.1fs)", skip ? "reasoning off" : "reasoning on",
                         -start.timeIntervalSinceNow))
            print("  dictionary form: \(gloss.dictionaryForm)")
            print("  meaning:         \(gloss.meaning)")
            print("  sentence:        \(gloss.sentence)")
        } catch {
            print("\n\(skip ? "reasoning off" : "reasoning on") failed: \(error)")
        }
    }
    exit(0)
}

if arguments.first == "--list" {
    let playing = AudioProcesses.playing()
    print(playing.isEmpty
        ? "nothing is playing audio right now"
        : "playing audio right now — this is what a session would tap:")
    for process in playing {
        print("  ▶ \(process.name.padding(toLength: 28, withPad: " ", startingAt: 0)) \(process.bundleID)")
    }

    let processes = AudioProcesses.running().sorted { $0.name.lowercased() < $1.name.lowercased() }
    print("\nall \(processes.count) audio processes:")
    for process in processes {
        let marker = process.isPlaying ? "▶" : " "
        print("  \(marker) \(process.name.padding(toLength: 28, withPad: " ", startingAt: 0)) \(process.bundleID)")
    }
    exit(0)
}

let locale = Locale(identifier: "de-DE")

print("checking the German model…")
try await Transcriber.ensureModel(locale: locale) { fraction in
    print(String(format: "  downloading %.0f%%", fraction * 100))
}
print("model ready")

let transcriber = Transcriber(locale: locale, speaker: .them)
try await transcriber.start()

let printer = Task {
    for await event in transcriber.events {
        switch event {
        case .line(let line):
            print(String(format: "\u{1B}[2K\r[%6.1fs] %@", line.start, line.text))
        case .volatile(_, let text):
            print("\u{1B}[2K\r         … \(text)", terminator: "")
            fflush(stdout)
        }
    }
}

switch arguments.first {
case "--file":
    guard let path = arguments.dropFirst().first else { fatalError("--file needs a path") }
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    // Paced at 1x by default: fed faster, the recognizer never sees a pause and
    // so never commits a line until the very end, which is not how a call
    // behaves. `--fast` dumps it in as quickly as possible for comparison.
    let paced = !arguments.contains("--fast")
    print("transcribing \(path)\(paced ? " at 1x" : " as fast as possible")")
    let chunk: Int64 = 4096
    while file.framePosition < file.length {
        let frames = AVAudioFrameCount(min(chunk, file.length - file.framePosition))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else { break }
        try file.read(into: buffer, frameCount: frames)
        if buffer.frameLength == 0 { break }
        transcriber.append(buffer)
        if paced {
            let seconds = Double(buffer.frameLength) / file.processingFormat.sampleRate
            try await Task.sleep(for: .seconds(seconds))
        }
    }

case "--tap":
    // With a name, tap that app. Without one, tap whatever is playing — which is
    // what a real session does, so this exercises the same path.
    let query = arguments.dropFirst().first.flatMap { Int($0) == nil ? $0 : nil }
    let processes = query.map(AudioProcesses.group) ?? AudioProcesses.likelyCall()
    guard !processes.isEmpty else {
        throw ProcessTapError.noSuchProcess(query ?? "anything playing audio")
    }
    let seconds = arguments.dropFirst().first(where: { Int($0) != nil }).flatMap(Int.init) ?? 60
    let tap = try ProcessTapSource(processes: processes)
    let names = processes.map { $0.bundleID.isEmpty ? $0.name : $0.bundleID }
    print("tapping \(processes.count) process(es): \(names.joined(separator: ", "))")
    print("format: \(tap.format)")

    // Peak level, so a silent tap is obvious rather than looking like a
    // transcription failure.
    let meter = Meter()
    try tap.start { buffer, _ in
        meter.observe(buffer)
        transcriber.append(buffer)
    }
    print("listening for \(seconds)s — play German audio in \(processes[0].name)")
    for _ in 0..<seconds {
        try await Task.sleep(for: .seconds(1))
        meter.reportIfQuiet()
    }
    tap.stop()
    print("peak level over the whole tap: \(String(format: "%.4f", meter.overallPeak))")

default:
    let seconds = arguments.first.flatMap(Int.init) ?? 30
    let mic = MicSource()
    try mic.start { buffer, time in transcriber.append(buffer, at: time) }
    print("listening for \(seconds)s — say something in German")
    try await Task.sleep(for: .seconds(seconds))
    mic.stop()
}

try await transcriber.finish()
_ = await printer.value
print("done")
