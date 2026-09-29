import CallCore
import MajorTomStyle
import SwiftUI

/// A conversation with the model, usually about one word. The model already
/// knows the word, its sentence and meaning, so you can go straight to the
/// question — "abstellen vs. ausschalten?" — and Back returns you to the word.
struct AskView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    let item: Item?
    @State private var chatID: Int64?
    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var reply = ""
    @State private var thinking = false
    @State private var sending = false
    @State private var failure: String?
    @State private var extracting = false
    @State private var cards: CardSet?
    @State private var savedCount: Int?
    @FocusState private var inputFocused: Bool

    /// Opens the latest conversation about `item`, or starts one.
    init(item: Item) {
        self.item = item
        _chatID = State(initialValue: nil)
    }

    /// Reopens a conversation from the AI tab, or starts a free one.
    init(chatID: Int64?, item: Item?) {
        self.item = item
        _chatID = State(initialValue: chatID)
    }

    var body: some View {
        VStack(spacing: 0) {
            FollowingScrollView(following: "\(messages.count) \(reply.count) \(thinking)") {
                VStack(alignment: .leading, spacing: 16) {
                    if let item { WordHeader(item: item) }
                    ForEach(messages) { Bubble(role: $0.role, text: $0.content) }
                    if sending {
                        if reply.isEmpty {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(thinking ? "Thinking…" : "Waiting for the model…")
                            }
                            .font(.rounded(14, .medium))
                            .foregroundStyle(Palette.secondary)
                        } else {
                            Bubble(role: .assistant, text: reply)
                        }
                    }
                    if messages.isEmpty && !sending {
                        suggestions
                    }
                    if let failure {
                        Label(failure, systemImage: "exclamationmark.triangle.fill")
                            .font(.rounded(13, .medium))
                            .foregroundStyle(Palette.warmText)
                            .textSelection(.enabled)
                    }
                    if let savedCount {
                        Label("Saved \(savedCount) to My words", systemImage: "checkmark.circle.fill")
                            .font(.rounded(13, .semibold))
                            .foregroundStyle(Palette.goodText)
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(28)
            }
            inputBar
        }
        .background(Palette.background)
        .navigationTitle(item?.text ?? "Ask")
        .toolbar {
            ToolbarItem {
                Button { extract() } label: {
                    if extracting {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Save to My words", systemImage: "square.and.arrow.down")
                    }
                }
                .help("Have the model turn this conversation into words for My words")
                .disabled(extracting || sending || !messages.contains { $0.role == .assistant })
            }
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .sheet(item: $cards) { set in
            SaveCardsSheet(cards: set.cards) { kept in
                for card in kept {
                    store.addOwnWord(card.word, translation: card.meaning, context: card.example)
                }
                savedCount = kept.count
                cards = nil
            } onCancel: { cards = nil }
        }
        .onAppear(perform: load)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(item.map { "Ask about “\($0.text)”…" } ?? "Ask anything about German…",
                      text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.rounded(16))
                .lineLimit(1...6)
                .focused($inputFocused)
                .onSubmit { send(draft) }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Button { send(draft) } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Palette.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityLabel("Send")
        }
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(Palette.raised)
    }

    /// Starting points, so the first question is one click away.
    private var suggestions: some View {
        let prompts = item.map { item in
            [
                "When would a native speaker use something else instead of “\(item.text)”?",
                "Is “\(item.text)” everyday German, or more bookish?",
                "Give me three natural example sentences with it.",
            ]
        } ?? [
            "What is the difference between abstellen and ausschalten?",
            "Which German words sound old-fashioned today?",
        ]
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(prompts, id: \.self) { prompt in
                Button { send(prompt) } label: {
                    Text(prompt)
                        .font(.rounded(14, .medium))
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(Palette.accentText)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func load() {
        if chatID == nil, let item { chatID = store.chatID(for: item) }
        if let chatID { messages = store.messages(in: chatID) }
        inputFocused = true
    }

    private var systemPrompt: String {
        item.map(ChatClient.wordPrompt(for:)) ?? ChatClient.tutorPrompt
    }

    private func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        if chatID == nil {
            chatID = store.createChat(about: item, title: item?.text ?? String(text.prefix(80)))
        }
        guard let chatID, let sent = store.addMessage(.user, text, to: chatID) else {
            failure = "Could not save the message."
            return
        }
        messages.append(sent)
        draft = ""
        failure = nil
        savedCount = nil
        sending = true
        reply = ""
        thinking = false

        let history = messages
        let system = systemPrompt
        Task {
            defer { sending = false }
            guard let settings = await Translations.modelSettings() else {
                failure = "No model set up. Add one in Settings."
                return
            }
            var answer = ""
            do {
                for try await chunk in ChatClient(settings: settings, apiKey: Settings.apiKey)
                    .stream(system: system, messages: history) {
                    switch chunk {
                    case .thinking: thinking = true
                    case .text(let piece):
                        answer += piece
                        reply = answer
                    }
                }
            } catch {
                failure = "\(error)"
            }
            // Kept even if you went back mid-answer, so it is there next time.
            let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let saved = store.addMessage(.assistant, trimmed, to: chatID) {
                messages.append(saved)
            }
            reply = ""
        }
    }

    private func extract() {
        extracting = true
        failure = nil
        savedCount = nil
        let history = messages
        Task {
            defer { extracting = false }
            guard let settings = await Translations.modelSettings() else {
                failure = "No model set up. Add one in Settings."
                return
            }
            do {
                let found = try await ChatClient(settings: settings, apiKey: Settings.apiKey)
                    .extractWords(from: history)
                if found.isEmpty {
                    failure = "The model found nothing to save in this conversation."
                } else {
                    cards = CardSet(cards: found)
                }
            } catch {
                failure = "\(error)"
            }
        }
    }

    /// Identifiable wrapper so the cards can drive a sheet.
    private struct CardSet: Identifiable {
        let id = UUID()
        let cards: [Flashcard]
    }
}

/// The word the conversation is about, kept in view above it.
private struct WordHeader: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(item.text).font(.rounded(28, .heavy))
                if !item.translation.isEmpty {
                    Text(item.translation)
                        .font(.rounded(17, .semibold))
                        .foregroundStyle(Palette.accentText)
                }
            }
            if !item.context.isEmpty {
                ContextSentence(sentence: item.context, word: item.text, size: 16)
            }
            if !item.usageNote.isEmpty {
                Text(item.usageNote)
                    .font(.rounded(14))
                    .foregroundStyle(Palette.warmText)
            }
        }
        .textSelection(.enabled)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct Bubble: View {
    let role: ChatMessage.Role
    let text: String

    var body: some View {
        let isUser = role == .user
        Text(Self.rendered(text))
            .font(.rounded(16))
            .foregroundStyle(isUser ? .white : Palette.text)
            .textSelection(.enabled)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(isUser ? Palette.accent : Palette.card,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            .padding(isUser ? .leading : .trailing, 60)
    }

    /// Bold and italics from the model's markdown, keeping its line breaks.
    private static func rendered(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

/// What the model pulled out of a conversation, to check and trim before it
/// goes into My words.
private struct SaveCardsSheet: View {
    @State var cards: [Flashcard]
    let onSave: ([Flashcard]) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save to My words").font(.rounded(22, .heavy))
            Text("Untick anything you don't want, and edit what the model wrote.")
                .font(.rounded(13))
                .foregroundStyle(Palette.secondary)
            ScrollView {
                VStack(spacing: 12) {
                    ForEach($cards) { $card in
                        HStack(alignment: .top, spacing: 12) {
                            Toggle("", isOn: $card.keep).labelsHidden()
                            VStack(alignment: .leading, spacing: 6) {
                                TextField("Word", text: $card.word).font(.rounded(18, .heavy))
                                TextField("Meaning", text: $card.meaning).font(.rounded(15))
                                    .foregroundStyle(Palette.accentText)
                                TextField("Example", text: $card.example, axis: .vertical)
                                    .font(.rounded(14))
                                    .foregroundStyle(Palette.secondary)
                            }
                            .textFieldStyle(.plain)
                        }
                        .opacity(card.keep ? 1 : 0.45)
                        .padding(14)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save \(cards.filter(\.keep).count)") { onSave(cards.filter(\.keep)) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!cards.contains(where: \.keep))
            }
        }
        .padding(24)
        .frame(width: 520, height: 480)
        .background(Palette.background)
    }
}
