import AVFoundation
import CoreMedia
import Foundation
import Speech

/// A phrase the recognizer has committed to. Words still being revised arrive
/// as `.volatile` and only become a line once the recognizer finalizes them —
/// so a line never changes under you after you have clicked a word in it.
public struct Line: Sendable, Identifiable, Hashable, Codable {
    public let id: UUID
    public let text: String
    /// Seconds from the start of the session. Becomes `item.position`.
    public let start: TimeInterval

    public init(id: UUID = UUID(), text: String, start: TimeInterval) {
        self.id = id
        self.text = text
        self.start = start
    }

    /// The sentence within this line that contains `word`, for `item.context`.
    /// A line is one turn of speech, which can run to several sentences; saving
    /// all of them as context would bury the word.
    public func sentence(containing word: String) -> String {
        let sentences = Line.split(text)
        return sentences.first { $0.localizedCaseInsensitiveContains(word) } ?? text
    }

    static func split(_ text: String) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { substring, _, _, _ in
            let trimmed = substring?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { sentences.append(trimmed) }
        }
        return sentences.isEmpty ? [text] : sentences
    }
}

/// Thin window onto the recognizer's asset inventory, so callers do not have to
/// import Speech just to ask what is on the machine.
public enum SpeechTranscriberLocales {
    public static var installed: [String] {
        get async { await SpeechTranscriber.installedLocales.map(\.identifier) }
    }

    public static var supported: [String] {
        get async { await SpeechTranscriber.supportedLocales.map(\.identifier) }
    }
}

public enum TranscriptEvent: Sendable {
    case line(Line)
    case volatile(String)
}

public enum TranscriberError: Error, CustomStringConvertible {
    case localeUnsupported(String)

    public var description: String {
        switch self {
        case .localeUnsupported(let id): return "no on-device speech model for \(id)"
        }
    }
}

/// One recognizer over one audio track: the other side of a call on the Mac,
/// or the room on the phone.
///
/// The recognizer only commits a line after roughly three and a half seconds of
/// silence. On a call that lands on turn boundaries, because the other
/// person's track is silent whenever you are the one talking. Forcing them to commit sooner was tried and is a dead end:
/// `SpeechAnalyzer.finalize(through:)` truncates the phrase it cuts, dropping
/// words, which is the one thing this app cannot afford to do.
public final class Transcriber: @unchecked Sendable {
    /// Which recognizer is doing the work.
    public enum Engine: String, Sendable {
        /// The iOS 26 / macOS 26 model. Better, but not on every device —
        /// `SpeechTranscriber.isAvailable` is false where the hardware cannot
        /// run it, which includes iPhones without Apple Intelligence.
        case speechTranscriber
        /// The dictation assets, which exist everywhere. The fallback.
        case dictationTranscriber
    }

    public let engine: Engine

    /// Which recognizer this device would use, answerable before starting
    /// anything — it is a property of the hardware, not of a session.
    public static var availableEngine: Engine {
        SpeechTranscriber.isAvailable ? .speechTranscriber : .dictationTranscriber
    }

    /// Both conform to `SpeechModule` and both produce a `Result` with the same
    /// shape, so only construction and the results loop differ.
    private enum Recognizer {
        case modern(SpeechTranscriber)
        case dictation(DictationTranscriber)

        var module: any SpeechModule {
            switch self {
            case .modern(let m): return m
            case .dictation(let m): return m
            }
        }
    }

    private let recognizer: Recognizer
    private let analyzer: SpeechAnalyzer
    private let input: AsyncStream<AnalyzerInput>
    private let feed: AsyncStream<AnalyzerInput>.Continuation
    /// Capture devices hand us whatever format they like; the recognizer wants
    /// one specific format. (macOS 27 has `AnalyzerInputConverter` for this, but
    /// we target 26, so the resampling is done by hand.)
    private var analyzerFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var framesFed: Int64 = 0

    public let events: AsyncStream<TranscriptEvent>
    private let emit: AsyncStream<TranscriptEvent>.Continuation
    private var pump: Task<Void, Never>?

    public init(locale: Locale) {
        engine = Transcriber.availableEngine
        if engine == .speechTranscriber {
            recognizer = .modern(SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                // Without `.fastResults` the analyzer reports nothing at all
                // until the stream is finalized — the whole call would arrive
                // at once, when it is already over. With it, volatile text
                // streams about once a second, which is what the live captions
                // are made of.
                reportingOptions: [.volatileResults, .fastResults],
                attributeOptions: [.audioTimeRange]
            ))
        } else {
            // `frequentFinalization` is this recognizer's equivalent knob.
            recognizer = .dictation(DictationTranscriber(
                locale: locale,
                contentHints: [],
                transcriptionOptions: [],
                reportingOptions: [.volatileResults, .frequentFinalization],
                attributeOptions: [.audioTimeRange]
            ))
        }
        analyzer = SpeechAnalyzer(modules: [recognizer.module])
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        input = stream
        feed = continuation
        let (out, emitter) = AsyncStream.makeStream(of: TranscriptEvent.self)
        events = out
        emit = emitter
    }

    /// Downloads the locale's model if it is not already on the machine. Only
    /// the first run needs the network; after that everything is local.
    public static func ensureModel(locale: Locale, progress: ((Double) -> Void)? = nil) async throws {
        let probe: any SpeechModule = SpeechTranscriber.isAvailable
            ? SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
            : DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
        switch await AssetInventory.status(forModules: [probe]) {
        case .installed:
            return
        case .unsupported:
            throw TranscriberError.localeUnsupported(locale.identifier)
        default:
            guard let request = try await AssetInventory.assetInstallationRequest(supporting: [probe]) else { return }
            let watcher = progress.map { report in
                Task {
                    while !Task.isCancelled {
                        report(request.progress.fractionCompleted)
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                }
            }
            defer { watcher?.cancel() }
            try await request.downloadAndInstall()
        }
    }

    public func start() async throws {
        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [recognizer.module])
        try await analyzer.prepareToAnalyze(in: analyzerFormat)
        pump = Task { [weak self] in await self?.drainResults() }
        try await analyzer.start(inputSequence: input)
    }

    public func append(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime? = nil) {
        guard let converted = resample(buffer) else { return }
        let start = CMTime(value: framesFed, timescale: CMTimeScale(converted.format.sampleRate))
        framesFed += Int64(converted.frameLength)
        feed.yield(AnalyzerInput(buffer: converted, bufferStartTime: start))
    }

    public func finish() async throws {
        feed.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        await pump?.value
        emit.finish()
    }

    private func drainResults() async {
        do {
            switch recognizer {
            case .modern(let module):
                for try await result in module.results {
                    handle(text: result.text, range: result.range, isFinal: result.isFinal)
                }
            case .dictation(let module):
                for try await result in module.results {
                    handle(text: result.text, range: result.range, isFinal: result.isFinal)
                }
            }
        } catch {
            // The analyzer finishing is the normal way this loop ends.
        }
    }

    private func handle(text attributed: AttributedString, range: CMTimeRange, isFinal: Bool) {
        let text = String(attributed.characters)
        guard isFinal else {
            emit.yield(.volatile(text))
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let start = range.start.seconds
        emit.yield(.line(Line(text: trimmed, start: start.isFinite ? start : 0)))
    }

    private func resample(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let target = analyzerFormat else { return nil }
        guard buffer.format != target else { return buffer }

        if converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
            converter?.primeMethod = .none
        }
        guard let converter else { return nil }

        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }

        // The converter pulls until it has enough input; we have exactly one
        // buffer to give, so the second pull reports "nothing right now".
        var offered = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if offered {
                outStatus.pointee = .noDataNow
                return nil
            }
            offered = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }
}
