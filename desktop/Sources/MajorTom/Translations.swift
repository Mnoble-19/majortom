import CallCore
import Foundation

/// Fills in meanings: every word still missing one, or a single word you want
/// checked. Words arrive untranslated from the phone, from calls, from the
/// reMarkable offline and from the browser when DeepL is down; all of them are
/// translated here.
@MainActor
final class Translations: ObservableObject {
    enum Outcome: Equatable {
        case translated(Int)
        case unavailable
        case failed(String)

        var message: String {
            switch self {
            case .translated(let n): return "Translated \(n) \(n == 1 ? "word" : "words")"
            case .unavailable:
                return "No translator set up. Add a model in Settings, or German under System Settings › General › Language & Region › Translation Languages."
            case .failed(let why): return why
            }
        }

        var isFailure: Bool {
            if case .translated = self { return false }
            return true
        }
    }

    @Published private(set) var running = false
    @Published private(set) var done = 0
    @Published private(set) var total = 0
    @Published private(set) var outcome: Outcome?

    private let store: Store

    init(store: Store) {
        self.store = store
    }

    /// Every word in scope that has no meaning yet.
    func translateWaiting(in scope: Scope = .all) {
        guard !running else { return }
        let pending = store.untranslatedItems(in: scope)
        guard !pending.isEmpty else { return }

        running = true
        done = 0
        total = pending.count
        outcome = nil

        Task {
            let settings = await Self.modelSettings()
            let translator = Translator(settings: settings ?? Settings.llm, apiKey: Settings.apiKey)
            var filled = 0
            for item in pending {
                var best: Gloss?
                for await gloss in translator.glosses(word: item.text, sentence: item.context) {
                    best = gloss
                }
                done += 1
                guard let best else { continue }
                store.applyTranslation(best.meaning, sentence: best.sentence,
                                       alternatives: best.alternatives, to: item)
                filled += 1
            }
            running = false
            let result: Outcome = filled > 0 ? .translated(filled)
                : settings != nil ? .failed("The model could not be reached — is it running?")
                : .unavailable
            outcome = result
            // A success fades on its own; a failure stays until it is fixed.
            if !result.isFailure {
                try? await Task.sleep(for: .seconds(6))
                if outcome == result { outcome = nil }
            }
        }
    }

    /// One word, from the model when there is one. Leaves the library alone:
    /// the caller decides whether the answer replaces what is there.
    func check(_ item: Item) async throws -> Gloss {
        if let settings = await Self.modelSettings() {
            return try await ModelTranslator(settings: settings, apiKey: Settings.apiKey)
                .gloss(word: item.text, sentence: item.context)
        }
        return try await AppleTranslator().gloss(word: item.text, sentence: item.context)
    }

    func dismiss() {
        outcome = nil
    }

    /// The model to use, or nil for none. With none picked yet, takes the
    /// first one the endpoint lists and remembers it, so a running server
    /// works without a trip to Settings.
    private static func modelSettings() async -> LLMSettings? {
        var settings = Settings.llm
        guard settings.enabled, !settings.endpoint.isEmpty else { return nil }
        if settings.model.isEmpty {
            let listed = try? await ModelTranslator(settings: settings, apiKey: Settings.apiKey).models()
            guard let first = listed?.first else { return nil }
            settings.model = first
            Settings.llm = settings
        }
        return settings
    }
}
