import AppKit
import CallCore
import MajorTomStyle
import SwiftUI

/// What the other person says, line by line. Every committed word can be
/// clicked to save it.
struct TranscriptView: View {
    let model: SessionModel

    var body: some View {
        FollowingScrollView(following: "\(model.lines.count) \(model.volatile)") {
            LazyVStack(alignment: .leading, spacing: 10) {
                Text("Click a word to save it · Shift-click another word in the line to save the phrase between")
                    .font(.rounded(12, .semibold))
                    .foregroundStyle(Palette.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 6)

                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.rounded(13, .medium))
                        .foregroundStyle(Palette.warmText)
                }

                ForEach(model.lines) { line in
                    Bubble {
                        FlowLayout(spacing: 3, lineSpacing: 3) {
                            ForEach(Array(line.text.split(separator: " ").enumerated()), id: \.offset) { index, token in
                                let word = String(token)
                                WordButton(
                                    word: word,
                                    isSaved: savedWords.contains(Self.bare(word)),
                                    isPhraseStart: model.phraseStart?.line == line.id
                                        && model.phraseStart?.index == index,
                                    action: {
                                        model.tap(index, in: line,
                                                  extending: NSEvent.modifierFlags.contains(.shift))
                                    })
                            }
                        }
                    }
                    .id(line.id)
                }

                // Heard but not committed. Not clickable: it is still being
                // revised, so a word here can change under the click.
                if !model.volatile.isEmpty {
                    Bubble(faded: true) {
                        Text(model.volatile).font(.rounded(18)).italic()
                    }
                }
            }
            .padding(24)
        }
    }

    /// Every word of every saved word or phrase, for highlighting.
    private var savedWords: Set<String> {
        Set(model.saved.flatMap { $0.word.lowercased().split(separator: " ").map(String.init) })
    }

    static func bare(_ word: String) -> String {
        word.trimmingCharacters(in: .punctuationCharacters).lowercased()
    }
}

private struct Bubble<Content: View>: View {
    var faded = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .foregroundStyle(Palette.text)
            .background(Palette.card, in: UnevenRoundedRectangle(
                topLeadingRadius: 20, bottomLeadingRadius: 6,
                bottomTrailingRadius: 20, topTrailingRadius: 20, style: .continuous))
            .opacity(faded ? 0.55 : 1)
            .padding(.trailing, 60)
    }
}

private struct WordButton: View {
    let word: String
    let isSaved: Bool
    let isPhraseStart: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Text(word)
            .font(.rounded(18, isSaved ? .bold : .regular))
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .foregroundStyle(isSaved ? Palette.onHighlight : Palette.text)
            .background(isSaved ? Palette.highlight : hovering ? Palette.raised : .clear,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isPhraseStart ? Palette.accent : .clear, lineWidth: 2))
            .help(isPhraseStart ? "Shift-click another word to save the phrase" : "")
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
    }
}

/// The words saved during this session. Editable, so a misheard word can be
/// corrected on the spot.
struct SavedWordsView: View {
    let words: [SavedWord]
    let onEdit: (SavedWord.ID, String, String) -> Void
    let onDelete: (SavedWord.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Saved").font(.rounded(15, .heavy))
                Spacer()
                Text("\(words.count)")
                    .font(.rounded(13, .heavy))
                    .foregroundStyle(Palette.onHighlight)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Palette.highlight, in: Capsule())
            }

            if words.isEmpty {
                Text("Click a word in the conversation and it lands here.")
                    .font(.rounded(13))
                    .foregroundStyle(Palette.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(words.reversed()) { word in
                            SavedWordRow(word: word, onEdit: onEdit, onDelete: onDelete)
                        }
                    }
                }
            }

            Text("Click a word or its sentence to fix or trim it. Translations are filled in by MajorTom afterwards.")
                .font(.rounded(11))
                .foregroundStyle(Palette.tertiary)
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.raised)
    }
}

/// A saved word and the sentence kept with it, both editable in place: fix a
/// misheard word, or cut the sentence down to what you are happy keeping.
struct SavedWordRow: View {
    let word: SavedWord
    let onEdit: (SavedWord.ID, String, String) -> Void
    let onDelete: (SavedWord.ID) -> Void

    @State private var text = ""
    @State private var sentence = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                TextField("Word", text: $text)
                    .font(.rounded(16, .heavy))
                Button { onDelete(word.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.tertiary)
                .help("Delete this word")
            }
            TextField("Sentence", text: $sentence, axis: .vertical)
                .font(.rounded(12))
                .foregroundStyle(Palette.secondary)
                .lineLimit(1...8)
        }
        .textFieldStyle(.plain)
        .focused($focused)
        .onSubmit(commit)
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
        .onAppear {
            text = word.word
            sentence = word.sentence
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func commit() {
        guard text != word.word || sentence != word.sentence else { return }
        onEdit(word.id, text, sentence)
    }
}
