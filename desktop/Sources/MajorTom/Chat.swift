import CallCore
import Foundation

/// One turn in a conversation with the model.
struct ChatMessage: Identifiable, Hashable {
    var id: Int64
    var role: Role
    var content: String

    enum Role: String {
        case user, assistant
    }
}

/// A conversation as the AI tab lists it.
struct ChatSummary: Identifiable, Hashable {
    var id: Int64
    var itemID: Int64?
    var title: String
    var updatedAt: Date
    var messageCount: Int
}

/// A word worth keeping, pulled out of a conversation for "My words".
struct Flashcard: Identifiable, Hashable {
    var id = UUID()
    var word: String
    var meaning: String
    var example: String
    var keep = true
}

/// Talks to the same local model that translates, but as a conversation:
/// replies stream in as they are written, since an answer can take a while.
struct ChatClient {
    let settings: LLMSettings
    let apiKey: String

    enum Chunk {
        /// The model is thinking before it answers.
        case thinking
        case text(String)
    }

    func stream(system: String, messages: [ChatMessage]) -> AsyncThrowingStream<Chunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var body = baseBody(system: system, messages: messages)
                    body["stream"] = true
                    let (bytes, response) = try await URLSession.shared.bytes(for: try request(body))
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw TranslatorError.http(http.statusCode, "")
                    }
                    // Server-sent events: one `data: {json}` line per piece.
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let event = try? JSONDecoder().decode(StreamEvent.self, from: Data(payload.utf8)),
                              let delta = event.choices.first?.delta else { continue }
                        if let text = delta.content, !text.isEmpty {
                            continuation.yield(.text(text))
                        } else if delta.reasoning_content?.isEmpty == false {
                            continuation.yield(.thinking)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Reads a finished conversation and pulls out the words worth keeping,
    /// each with a meaning and an example — what "Save to My words" offers.
    func extractWords(from messages: [ChatMessage]) async throws -> [Flashcard] {
        let transcript = messages.map { "\($0.role == .user ? "Learner" : "Tutor"): \($0.content)" }
            .joined(separator: "\n\n")
        var body = baseBody(system: Self.extractPrompt,
                            messages: [ChatMessage(id: 0, role: .user, content: transcript)])
        body["response_format"] = [
            "type": "json_schema",
            "json_schema": [
                "name": "cards",
                "strict": true,
                "schema": [
                    "type": "object",
                    "properties": [
                        "cards": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "word": ["type": "string"],
                                    "meaning": ["type": "string"],
                                    "example": ["type": "string"]
                                ],
                                "required": ["word", "meaning", "example"],
                                "additionalProperties": false
                            ]
                        ]
                    ],
                    "required": ["cards"],
                    "additionalProperties": false
                ]
            ]
        ]
        let (data, response) = try await URLSession.shared.data(for: try request(body))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TranslatorError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        guard let message = reply.choices.first?.message else { throw TranslatorError.emptyReply }
        let text = message.content?.isEmpty == false ? message.content! : (message.reasoning_content ?? "")
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let cards = try? JSONDecoder().decode(Cards.self, from: Data(text[start...end].utf8))
        else { throw TranslatorError.emptyReply }

        return cards.cards.compactMap { card in
            let word = card.word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { return nil }
            return Flashcard(word: word,
                            meaning: card.meaning.trimmingCharacters(in: .whitespacesAndNewlines),
                            example: card.example.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func baseBody(system: String, messages: [ChatMessage]) -> [String: Any] {
        var body: [String: Any] = [
            "model": settings.model,
            "temperature": 0.4,
            "max_tokens": settings.maxTokens,
            "messages": [["role": "system", "content": system]]
                + messages.map { ["role": $0.role.rawValue, "content": $0.content] },
        ]
        if settings.skipReasoning { body["reasoning_effort"] = "none" }
        return body
    }

    private func request(_ body: [String: Any]) throws -> URLRequest {
        guard !settings.endpoint.isEmpty, let base = URL(string: settings.endpoint) else {
            throw TranslatorError.badEndpoint(settings.endpoint)
        }
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

    // MARK: - Prompts

    static let tutorPrompt = """
        You are a German tutor for someone at B2/C1 who wants to sound native. \
        They ask about words they met in books, shows and conversations: how a \
        word differs from a near-synonym, when one is more natural, what register \
        it has, how people actually say it today. Answer in English with German \
        examples. Be direct and brief — a few sentences or a short list, not an \
        essay — and give a short example sentence when it helps. If a word is \
        dated, bookish or regional, say so and give the everyday alternative.
        """

    /// What the model knows about the word a conversation is about.
    static func wordPrompt(for item: Item) -> String {
        var lines = [tutorPrompt, "", "The conversation is about this word:",
                     "word: \(item.text)"]
        if !item.translation.isEmpty { lines.append("meaning: \(item.translation)") }
        if !item.context.isEmpty { lines.append("sentence: \(item.context)") }
        if !item.contextTranslation.isEmpty { lines.append("sentence in English: \(item.contextTranslation)") }
        if !item.alternatives.isEmpty { lines.append("alternatives: \(item.alternatives.joined(separator: ", "))") }
        if !item.register.isEmpty { lines.append("register: \(item.register)") }
        if !item.usageNote.isEmpty { lines.append("note: \(item.usageNote)") }
        lines.append("met in: \(item.origin)")
        return lines.joined(separator: "\n")
    }

    private static let extractPrompt = """
        You are given a conversation between a German learner and a tutor. \
        Pull out the German words or short phrases the learner would want on \
        flashcards: the ones the conversation was about, and any alternative \
        that was explained well enough to learn from it. Usually one to four; \
        never pad the list. For each give `word` in dictionary form (infinitive, \
        or noun with its article), `meaning` as a short English gloss that \
        captures the distinction discussed, and `example` as one natural German \
        sentence using it.
        """

    // MARK: - Wire types

    private struct StreamEvent: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
                let reasoning_content: String?
            }
            let delta: Delta?
        }
        let choices: [Choice]
    }

    private struct Reply: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
                let reasoning_content: String?
            }
            let message: Message
        }
        let choices: [Choice]
    }

    private struct Cards: Decodable {
        struct Card: Decodable {
            let word: String
            let meaning: String
            let example: String
        }
        let cards: [Card]
    }
}
