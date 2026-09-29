import CallCore
import Foundation

/// Fills in meanings: every word still missing one, or a single word you want
/// checked. Words arrive untranslated from the phone, from calls, from the
/// reMarkable offline and from the browser when its model is down; all of them are
/// translated here.
@MainActor
final class Translations: ObservableObject {
    enum Outcome: Equatable {
        case translated(Int)
        case reviewed(Int)
        case unavailable
        case failed(String)

        var message: String {
            switch self {
            case .translated(let n): return "Translated \(n) \(n == 1 ? "word" : "words")"
            case .reviewed(let n): return "Reviewed \(n) \(n == 1 ? "word" : "words")"
            case .unavailable:
                return "No translator set up. Add a model in Settings, or German under System Settings › General › Language & Region › Translation Languages."
            case .failed(let why): return why
            }
        }

        var isFailure: Bool {
            switch self {
            case .translated, .reviewed: return false
            default: return true
            }
        }
    }

    @Published private(set) var running = false
    /// Which job is running: filling in missing meanings, or reviewing words
    /// that already have one.
    @Published private(set) var reviewing = false
    @Published private(set) var done = 0
    @Published private(set) var total = 0
    @Published private(set) var outcome: Outcome?

    private let store: Store

    init(store: Store) {
        self.store = store
    }

    /// Every word in scope that has no meaning yet.
    func translateWaiting(in scope: Scope = .all) {
        run(store.untranslatedItems(in: scope), reviewing: false)
    }

    /// Has the model look again at words that already have a meaning — from
    /// the browser, or from before usage notes — for alternatives and a note,
    /// leaving the meaning itself alone.
    func reviewWaiting(in scope: Scope = .all) {
        run(store.unenrichedItems(in: scope), reviewing: true)
    }

    /// Words go to the model five at a time: a thinking model spends most of a
    /// request getting going, so a batch costs little more than one word. With
    /// no model, Apple's translator fills in meanings one word at a time — it
    /// has nothing to add to a review, so a review needs the model.
    private func run(_ pending: [Item], reviewing: Bool) {
        guard !running, !pending.isEmpty else { return }

        running = true
        self.reviewing = reviewing
        done = 0
        total = pending.count
        outcome = nil

        Task {
            var filled = 0
            var lastError: String?
            let settings = await Self.modelSettings()

            for batch in pending.chunked(into: Self.batchSize) {
                var answers: [Result<Gloss, Error>]
                if let settings {
                    do {
                        answers = try await ModelTranslator(settings: settings, apiKey: Settings.apiKey)
                            .glosses(batch.map(\.question))
                    } catch {
                        answers = Array(repeating: .failure(error), count: batch.count)
                    }
                } else {
                    answers = Array(repeating: .failure(TranslatorError.notConfigured), count: batch.count)
                }
                for (item, answer) in zip(batch, answers) {
                    var answer = answer
                    if case .failure = answer, !reviewing {
                        let apple = try? await AppleTranslator().gloss(word: item.text, sentence: item.context)
                        if let apple { answer = .success(apple) }
                    }
                    switch answer {
                    case .success(let gloss):
                        store.apply(gloss, meaning: reviewing ? item.translation : nil, to: item)
                        filled += 1
                    case .failure(TranslatorError.notConfigured):
                        break
                    case .failure(let error):
                        lastError = "\(error)"
                    }
                    done += 1
                }
            }

            running = false
            self.reviewing = false
            let result: Outcome = filled > 0 ? (reviewing ? .reviewed(filled) : .translated(filled))
                : lastError.map { .failed("\(reviewing ? "Review" : "Translation") failed: \($0)") } ?? .unavailable
            outcome = result
            // A success fades on its own; a failure stays until it is fixed.
            if !result.isFailure {
                try? await Task.sleep(for: .seconds(6))
                if outcome == result { outcome = nil }
            }
        }
    }

    private static let batchSize = 5

    /// One word, from the model when there is one. Leaves the library alone:
    /// the caller decides whether the answer replaces what is there.
    func check(_ item: Item) async throws -> Gloss {
        if let settings = await Self.modelSettings() {
            return try await ModelTranslator(settings: settings, apiKey: Settings.apiKey)
                .glosses([item.question])[0].get()
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

private extension Item {
    var question: ModelTranslator.Question {
        .init(word: text, sentence: context, from: origin)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

extension Store {
    /// Takes everything the translator gave. `meaning` defaults to its gloss,
    /// but can be the one you typed, keeping it while taking the rest.
    func apply(_ gloss: Gloss, meaning: String? = nil, to item: Item) {
        applyTranslation(meaning ?? gloss.meaning, sentence: gloss.sentence,
                         alternatives: gloss.alternatives, register: gloss.register,
                         note: gloss.usageNote, byModel: gloss.origin == .model, to: item)
    }
}
