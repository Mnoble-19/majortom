import Foundation
import Translation

/// What clicking a word produces.
public struct Gloss: Sendable, Equatable {
    /// The form you would look up — `abbringen`, not `abbringen lassen`.
    public var dictionaryForm: String
    /// What it means *here*. The whole reason a model is involved.
    public var meaning: String
    /// The surrounding sentence in English.
    public var sentence: String
    /// Other German words for the same meaning, a small thesaurus. Only the
    /// model gives these; Apple's translator leaves it empty.
    public var alternatives: [String] = []
    public var origin: Origin

    public enum Origin: String, Sendable {
        /// Apple's on-device translator: instant, no setup, context-blind.
        case apple
        /// The local model: slower, understands how the word was used.
        case model
    }
}

public enum TranslatorError: Error, CustomStringConvertible {
    case notConfigured
    case badEndpoint(String)
    case http(Int, String)
    case emptyReply
    case implausible(String)
    case languagePackMissing

    public var description: String {
        switch self {
        case .notConfigured: return "no model endpoint set"
        case .badEndpoint(let s): return "\(s) is not a URL"
        case .http(let code, let body):
            return "the endpoint answered \(code)\(body.isEmpty ? "" : " — \(body)")"
        case .emptyReply: return "the model returned nothing"
        case .implausible(let why): return "the model's answer was rejected — \(why)"
        case .languagePackMissing:
            return "macOS has no German→English translation installed"
        }
    }
}

/// Apple's on-device translator. Fast enough to feel instant, and always there
/// — which is what makes it the floor rather than the ceiling. It translates a
/// word without knowing how it was used, so `anziehen` comes back as "to put
/// on" whether the speaker meant clothes or the weather turning cold.
public struct AppleTranslator: Sendable {
    private let source: Locale.Language
    private let target: Locale.Language

    public init(source: String = "de", target: String = "en") {
        self.source = Locale.Language(identifier: source)
        self.target = Locale.Language(identifier: target)
    }

    public func isAvailable() async -> Bool {
        await LanguageAvailability().status(from: source, to: target) == .installed
    }

    public func gloss(word: String, sentence: String) async throws -> Gloss {
        guard await isAvailable() else { throw TranslatorError.languagePackMissing }
        let session = TranslationSession(installedSource: source, target: target)
        let responses = try await session.translations(from: [
            .init(sourceText: word, clientIdentifier: "word"),
            .init(sourceText: sentence, clientIdentifier: "sentence")
        ])
        let byID = Dictionary(
            uniqueKeysWithValues: responses.map { ($0.clientIdentifier ?? "", $0.targetText) })
        return Gloss(
            dictionaryForm: word,
            meaning: byID["word"] ?? "",
            sentence: byID["sentence"] ?? "",
            origin: .apple
        )
    }
}

/// Any OpenAI-compatible endpoint — LM Studio, llama.cpp, Ollama, Unsloth.
/// One HTTP client rather than one integration per tool.
public struct ModelTranslator: Sendable {
    private let settings: LLMSettings
    private let apiKey: String

    public init(settings: LLMSettings, apiKey: String) {
        self.settings = settings
        self.apiKey = apiKey
    }

    /// Only the word and its one sentence are sent — never more of the
    /// conversation than the library itself keeps.
    public func gloss(word: String, sentence: String) async throws -> Gloss {
        do {
            return try await ask(word: word, sentence: sentence, schema: true)
        } catch TranslatorError.http(let code, let body) where Self.rejectedTheSchema(code, body) {
            // Not every OpenAI-compatible server implements `response_format`
            // with a JSON schema — Ollama takes a plain `json` mode, some older
            // llama.cpp builds take nothing. Ask again without it and lean on
            // the prompt plus the brace extraction below.
            return try await ask(word: word, sentence: sentence, schema: false)
        }
    }

    private func ask(word: String, sentence: String, schema: Bool) async throws -> Gloss {
        let payload = try request(word: word, sentence: sentence, schema: schema)
        let (data, response) = try await URLSession.shared.data(for: payload)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TranslatorError.http(http.statusCode, String(body.prefix(300)))
        }

        let reply = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let message = reply.choices.first?.message else { throw TranslatorError.emptyReply }

        // A reasoning model puts its answer in `content` and its thinking in
        // `reasoning_content`, but truncates into the latter if it runs out of
        // room — so fall back to digging the JSON out of the thinking rather
        // than losing an answer that is sitting right there.
        let text = message.content?.isEmpty == false
            ? message.content!
            : (message.reasoning_content ?? "")
        guard let decoded = Answer.extract(from: text) else { throw TranslatorError.emptyReply }

        return try validated(decoded, word: word, sentence: sentence)
    }

    /// Nothing reaches the library unchecked. A model that answers in the wrong
    /// language, or with nothing at all, would otherwise write a blank or a
    /// German "translation" over a word and look like it had worked.
    private func validated(_ answer: Answer, word: String, sentence: String) throws -> Gloss {
        func tidy(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
        }

        let meaning = tidy(answer.english_meaning)
        var english = tidy(answer.english_sentence)
        let form = tidy(answer.dictionary_form)
        var seen = Set([word.lowercased(), form.lowercased()])
        let alternatives = (answer.german_synonyms ?? [])
            .map(tidy)
            .filter { !$0.isEmpty && $0.count <= 60 && seen.insert($0.lowercased()).inserted }

        guard !meaning.isEmpty else { throw TranslatorError.emptyReply }
        // A gloss is a few words. A paragraph means the model ignored the
        // instruction, and storing it would wreck the review screen.
        guard meaning.count <= Self.maxMeaning else {
            throw TranslatorError.implausible("the gloss came back \(meaning.count) characters long")
        }
        // The exact German back again is the failure mode that renaming the
        // fields fixed; catch it in case another model does it too.
        if english.compare(sentence, options: .caseInsensitive) == .orderedSame {
            english = ""
        }

        return Gloss(
            dictionaryForm: form.isEmpty ? word : form,
            meaning: meaning,
            sentence: english,
            alternatives: Array(alternatives.prefix(Self.maxAlternatives)),
            origin: .model
        )
    }

    private static let maxMeaning = 300
    private static let maxAlternatives = 5

    private static func rejectedTheSchema(_ code: Int, _ body: String) -> Bool {
        guard (400..<500).contains(code) else { return false }
        let lowered = body.lowercased()
        return lowered.contains("response_format")
            || lowered.contains("json_schema")
            || lowered.contains("schema")
    }

    /// Round-trips the endpoint the way the Test button needs: reachable, model
    /// name accepted, reply parseable.
    public func test() async throws -> Gloss {
        try await gloss(
            word: "abbringen",
            sentence: "Sie hat sich nicht davon abbringen lassen.")
    }

    public func models() async throws -> [String] {
        guard let base = URL(string: settings.endpoint) else {
            throw TranslatorError.badEndpoint(settings.endpoint)
        }
        var request = URLRequest(url: base.appending(path: "models"))
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TranslatorError.http(http.statusCode, "")
        }
        return try JSONDecoder().decode(ModelList.self, from: data).data.map(\.id)
    }

    private func request(word: String, sentence: String, schema: Bool) throws -> URLRequest {
        guard !settings.endpoint.isEmpty, let base = URL(string: settings.endpoint) else {
            throw TranslatorError.badEndpoint(settings.endpoint)
        }

        var body: [String: Any] = [
            "model": settings.model,
            "temperature": 0.2,
            // Generous, because a reasoning model spends most of this thinking
            // and a low ceiling truncates it before it ever answers.
            "max_tokens": 900,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": "word: \(word)\nsentence: \(sentence)"]
            ],
        ]
        if schema {
            // Constrained decoding, so the reply is always parseable instead of
            // prose wrapped around JSON.
            body["response_format"] = [
                "type": "json_schema",
                "json_schema": [
                    "name": "gloss",
                    "strict": true,
                    "schema": [
                        "type": "object",
                        "properties": [
                            "dictionary_form": ["type": "string"],
                            "english_meaning": ["type": "string"],
                            "english_sentence": ["type": "string"],
                            "german_synonyms": ["type": "array", "items": ["type": "string"]]
                        ],
                        "required": ["dictionary_form", "english_meaning", "english_sentence", "german_synonyms"],
                        "additionalProperties": false
                    ]
                ]
            ]
        }
        if settings.skipReasoning { body["reasoning_effort"] = "none" }

        var request = URLRequest(url: base.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        // A cold llama.cpp has to load the model before it answers at all.
        request.timeoutInterval = 180
        return request
    }

    private static let systemPrompt = """
        You help someone learning German. You are given a German word or phrase \
        and the sentence it was spoken in.

        Fill in the fields. `dictionary_form` is the infinitive for a verb, or \
        the nominative singular with its article for a noun. `english_meaning` \
        is a short English gloss of what the word means *in this context* — if \
        it has several senses, give the one actually used here rather than \
        listing them all. `english_sentence` is the sentence translated into \
        English. `german_synonyms` lists up to five other German words or short \
        phrases that mean the same thing in this context, most common first; \
        leave it empty if there are none. Write English in the English fields \
        and German in the German one.
        """

    // MARK: - Wire types

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
                let reasoning_content: String?
            }
            let message: Message
        }
        let choices: [Choice]
    }

    private struct ModelList: Decodable {
        struct Entry: Decodable { let id: String }
        let data: [Entry]
    }

    /// The field names carry their own instructions. With grammar-constrained
    /// decoding that matters more than the prompt does: called `sentence`, the
    /// model echoed the German back untranslated and leaked stray tokens into
    /// `meaning`; renamed to `english_sentence`, the same model got it right.
    private struct Answer: Decodable {
        let dictionary_form: String
        let english_meaning: String
        let english_sentence: String
        /// Optional so a model that ignores it still yields a usable gloss.
        let german_synonyms: [String]?

        /// Tolerant of a model that wraps its JSON in prose or a code fence.
        static func extract(from text: String) -> Answer? {
            if let direct = try? JSONDecoder().decode(Answer.self, from: Data(text.utf8)) {
                return direct
            }
            guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
                  start < end else { return nil }
            let slice = String(text[start...end])
            return try? JSONDecoder().decode(Answer.self, from: Data(slice.utf8))
        }
    }
}

/// Runs both providers so a click gets an answer immediately and a better one
/// shortly after. Nothing here touches the audio pipeline — a slow or dead
/// model delays a translation and nothing else.
public struct Translator: Sendable {
    private let apple = AppleTranslator()
    private let settings: LLMSettings
    private let apiKey: String

    public init(settings: LLMSettings = Settings.llm, apiKey: String = Settings.apiKey) {
        self.settings = settings
        self.apiKey = apiKey
    }

    /// Yields the fast answer first, then the good one. Either may be missing:
    /// with no language pack there is no fast answer, with no model running
    /// there is no good one, and with neither the stream simply ends empty.
    public func glosses(word: String, sentence: String) -> AsyncStream<Gloss> {
        AsyncStream { continuation in
            let task = Task {
                if let quick = try? await apple.gloss(word: word, sentence: sentence) {
                    continuation.yield(quick)
                }
                if settings.enabled, !settings.model.isEmpty {
                    let model = ModelTranslator(settings: settings, apiKey: apiKey)
                    if let better = try? await model.gloss(word: word, sentence: sentence) {
                        continuation.yield(better)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
