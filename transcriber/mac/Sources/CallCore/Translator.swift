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
    /// How the word sits in today's German — "colloquial", "dated" and so on
    /// — or empty for an ordinary word, which is most of them.
    public var register: String = ""
    /// Said only when it matters: the word is bookish, dialect, ruder than it
    /// looks, or has a more natural everyday alternative. Usually empty.
    public var usageNote: String = ""
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
    /// Thinking used the whole reply budget before any answer was written —
    /// usually the model going round in circles rather than a hard word.
    case ranOutThinking
    case implausible(String)
    case languagePackMissing

    public var description: String {
        switch self {
        case .notConfigured: return "no model endpoint set"
        case .badEndpoint(let s): return "\(s) is not a URL"
        case .http(let code, let body):
            return "the endpoint answered \(code)\(body.isEmpty ? "" : " — \(body)")"
        case .emptyReply: return "the model returned nothing"
        case .ranOutThinking: return "the model thought until it ran out of room and never answered"
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

    /// `context` is the utterances either side, which is what lets the model
    /// tell one sense of a word from another. `from` says where the word was
    /// met — "the novel “Krieg und Frieden”" — so it can tell a bookish word
    /// from an everyday one.
    public func gloss(word: String, sentence: String, context: [String] = [], from: String = "") async throws -> Gloss {
        let question = Question(word: word, sentence: sentence, context: context, from: from)
        return try await glosses([question])[0].get()
    }

    /// One word to translate, with what the model needs to pick its sense.
    public struct Question: Sendable {
        public let word: String
        public let sentence: String
        public let context: [String]
        public let from: String

        public init(word: String, sentence: String, context: [String] = [], from: String = "") {
            self.word = word
            self.sentence = sentence
            self.context = context
            self.from = from
        }
    }

    /// Several words in one request. A thinking model spends most of its time
    /// getting going, so five words at once cost little more than one. Each
    /// answer is checked on its own: one bad gloss fails that word, not the
    /// batch.
    public func glosses(_ questions: [Question]) async throws -> [Result<Gloss, Error>] {
        guard !questions.isEmpty else { return [] }
        do {
            return try await ask(questions, schema: true)
        } catch TranslatorError.http(let code, let body) where Self.rejectedTheSchema(code, body) {
            // Not every OpenAI-compatible server implements `response_format`
            // with a JSON schema — Ollama takes a plain `json` mode, some older
            // llama.cpp builds take nothing. Ask again without it and lean on
            // the prompt plus the brace extraction below.
            return try await ask(questions, schema: false)
        }
    }

    private func ask(_ questions: [Question], schema: Bool) async throws -> [Result<Gloss, Error>] {
        let payload = try request(questions, schema: schema)
        let (data, response) = try await URLSession.shared.data(for: payload)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TranslatorError.http(http.statusCode, String(body.prefix(300)))
        }

        let reply = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let choice = reply.choices.first else { throw TranslatorError.emptyReply }
        let message = choice.message
        if choice.finish_reason == "length", message.content?.isEmpty != false {
            throw TranslatorError.ranOutThinking
        }

        // A reasoning model puts its answer in `content` and its thinking in
        // `reasoning_content`, but truncates into the latter if it runs out of
        // room — so fall back to digging the JSON out of the thinking rather
        // than losing an answer that is sitting right there.
        let text = message.content?.isEmpty == false
            ? message.content!
            : (message.reasoning_content ?? "")
        guard let answers = Batch.extract(from: text)?.words else { throw TranslatorError.emptyReply }

        // Answers come back in the order asked. A model that drops one leaves
        // the rest where they were, so a short list fails only its tail.
        return questions.enumerated().map { index, question in
            guard index < answers.count else { return .failure(TranslatorError.emptyReply) }
            return Result { try validated(answers[index], word: question.word, sentence: question.sentence) }
        }
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

        let register = tidy(answer.register ?? "").lowercased()
        let note = tidy(answer.usage_note ?? "")

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
            register: Self.registers.contains(register) ? register : "",
            usageNote: note.count <= Self.maxNote ? note : "",
            origin: .model
        )
    }

    private static let maxMeaning = 300
    private static let maxAlternatives = 5
    private static let maxNote = 400
    /// Everything but "neutral", which is stored as empty so that only the
    /// words worth flagging carry a label.
    private static let registers: Set<String> = [
        "colloquial", "formal", "literary", "dated", "regional", "vulgar",
    ]

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

    private func request(_ questions: [Question], schema: Bool) throws -> URLRequest {
        guard !settings.endpoint.isEmpty, let base = URL(string: settings.endpoint) else {
            throw TranslatorError.badEndpoint(settings.endpoint)
        }

        var body: [String: Any] = [
            "model": settings.model,
            // Gemma's own recommended sampling. At a low temperature a
            // thinking model goes round in circles until it runs out of room.
            "temperature": 1.0,
            "top_p": 0.95,
            "top_k": 64,
            "max_tokens": settings.maxTokens,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": Self.userPrompt(questions)]
            ],
        ]
        if schema {
            // Constrained decoding, so the reply is always parseable instead of
            // prose wrapped around JSON — and holds exactly one answer a word.
            let answer: [String: Any] = [
                "type": "object",
                "properties": [
                    "dictionary_form": ["type": "string"],
                    "english_meaning": ["type": "string"],
                    "english_sentence": ["type": "string"],
                    "german_synonyms": ["type": "array", "items": ["type": "string"]],
                    "register": ["type": "string", "enum": ["neutral"] + Self.registers.sorted()],
                    "usage_note": ["type": "string"]
                ],
                "required": ["dictionary_form", "english_meaning", "english_sentence", "german_synonyms",
                             "register", "usage_note"],
                "additionalProperties": false
            ]
            body["response_format"] = [
                "type": "json_schema",
                "json_schema": [
                    "name": "glosses",
                    "strict": true,
                    "schema": [
                        "type": "object",
                        "properties": [
                            "words": [
                                "type": "array", "items": answer,
                                "minItems": questions.count, "maxItems": questions.count
                            ]
                        ],
                        "required": ["words"],
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
        request.timeoutInterval = settings.timeout
        return request
    }

    private static let systemPrompt = """
        You help someone learning German. They are at B2/C1: they understand \
        most things and want to sound native. You are given one or more \
        numbered German words or phrases, each with the sentence it was met \
        in, sometimes with the lines around it, and where it came from.

        Answer every one, in order, as an entry in `words`. Each word is on its \
        own: judge it by its own sentence. For each, fill in the fields. `dictionary_form` is the infinitive for a verb, or \
        the nominative singular with its article for a noun. `english_meaning` \
        is a short English gloss of what the word means *in this context* — if \
        it has several senses, give the one actually used here rather than \
        listing them all. `english_sentence` is the sentence translated into \
        English. `german_synonyms` lists up to five other German words or short \
        phrases that mean the same thing in this context, most common first; \
        leave it empty if there are none. Write English in the English fields \
        and German in the German one.

        `register` is how the word sits in today's German: "neutral" for \
        ordinary words a native speaker would use anywhere — most words are \
        this — or "colloquial", "formal", "literary", "dated", "regional" or \
        "vulgar" when it clearly is one of those.

        `usage_note` is usually empty. Write one only when a fluent learner \
        would likely use the word wrongly without it: it is dated or bookish and \
        people now say something else, it is dialect, it is much ruder or more \
        formal than it looks, or a close alternative means something subtly \
        different. Keep it to one short sentence, under 20 words, and name the \
        everyday alternative when there is one. Do not explain the meaning \
        again, and never write a note just to say the word is common. Decide \
        quickly: if nothing stands out at once, leave it empty.
        """

    private static func userPrompt(_ questions: [Question]) -> String {
        questions.enumerated().map { index, question in
            var lines = ["\(index + 1).", "word: \(question.word)", "sentence: \(question.sentence)"]
            if !question.from.isEmpty {
                lines.append("from: \(question.from)")
            }
            if !question.context.isEmpty {
                lines.append("surrounding conversation:")
                lines.append(contentsOf: question.context.map { "  \($0)" })
            }
            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    // MARK: - Wire types

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
                let reasoning_content: String?
            }
            let message: Message
            let finish_reason: String?
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
        let register: String?
        let usage_note: String?

    }

    private struct Batch: Decodable {
        let words: [Answer]

        /// Tolerant of a model that wraps its JSON in prose or a code fence.
        static func extract(from text: String) -> Batch? {
            if let direct = try? JSONDecoder().decode(Batch.self, from: Data(text.utf8)) {
                return direct
            }
            guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
                  start < end else { return nil }
            let slice = String(text[start...end])
            return try? JSONDecoder().decode(Batch.self, from: Data(slice.utf8))
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
    public func glosses(word: String, sentence: String, context: [String] = []) -> AsyncStream<Gloss> {
        AsyncStream { continuation in
            let task = Task {
                if let quick = try? await apple.gloss(word: word, sentence: sentence) {
                    continuation.yield(quick)
                }
                if settings.enabled, !settings.model.isEmpty {
                    let model = ModelTranslator(settings: settings, apiKey: apiKey)
                    if let better = try? await model.gloss(word: word, sentence: sentence, context: context) {
                        continuation.yield(better)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
