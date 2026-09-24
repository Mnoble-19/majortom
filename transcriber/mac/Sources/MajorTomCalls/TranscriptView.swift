import CallCore
import MajorTomStyle
import SwiftUI

/// The live conversation as a chat: their lines on the left, yours on the
/// right. The speaker comes free from which audio track a line arrived on.
struct TranscriptView: View {
    let model: SessionModel

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(spacing: 10) {
                    Text("Click any word to save it")
                        .font(.rounded(12, .semibold))
                        .foregroundStyle(Palette.tertiary)
                        .padding(.bottom, 6)

                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.rounded(13, .medium))
                            .foregroundStyle(Palette.warmText)
                    }

                    ForEach(model.lines) { line in
                        Bubble(isMine: line.speaker == .me) {
                            FlowLayout(spacing: 3, lineSpacing: 3) {
                                ForEach(Array(line.text.split(separator: " ").enumerated()), id: \.offset) { _, token in
                                    let word = String(token)
                                    WordButton(
                                        word: word,
                                        isMine: line.speaker == .me,
                                        isSaved: savedWords.contains(Self.bare(word)),
                                        action: { model.save(word: word, from: line) })
                                }
                            }
                        }
                        .id(line.id)
                    }

                    // Heard but not committed. Not clickable: it is still being
                    // revised, so a word here can change under the click.
                    ForEach(Speaker.allCasesInOrder, id: \.self) { speaker in
                        if let text = model.volatile[speaker], !text.isEmpty {
                            Bubble(isMine: speaker == .me, faded: true) {
                                Text(text).font(.rounded(18)).italic()
                            }
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(24)
            }
            .onChange(of: model.lines.count) { _, _ in
                withAnimation { scroll.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: model.volatile) { _, _ in
                scroll.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private var savedWords: Set<String> {
        Set(model.saved.map { $0.word.lowercased() })
    }

    static func bare(_ word: String) -> String {
        word.trimmingCharacters(in: .punctuationCharacters).lowercased()
    }
}

extension Speaker {
    /// Their line above yours, so the volatile tail reads in the order you would
    /// expect rather than whatever the dictionary hands back.
    static var allCasesInOrder: [Speaker] { [.them, .me] }
}

private struct Bubble<Content: View>: View {
    let isMine: Bool
    var faded = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 80) }
            content()
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .foregroundStyle(isMine ? .white : Palette.text)
                .background(isMine ? Palette.accent : Palette.card, in: shape)
                .opacity(faded ? 0.55 : 1)
            if !isMine { Spacer(minLength: 80) }
        }
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 20, bottomLeadingRadius: isMine ? 20 : 6,
            bottomTrailingRadius: isMine ? 6 : 20, topTrailingRadius: 20, style: .continuous)
    }
}

private struct WordButton: View {
    let word: String
    let isMine: Bool
    let isSaved: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Text(word)
            .font(.rounded(18, isSaved ? .bold : .regular))
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .foregroundStyle(isSaved ? Palette.onHighlight : isMine ? .white : Palette.text)
            .background(background, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
    }

    private var background: Color {
        if isSaved { return Palette.highlight }
        if hovering { return isMine ? .white.opacity(0.22) : Palette.raised }
        return .clear
    }
}

/// The words saved during this session. Editable, so a misheard word can be
/// corrected on the spot.
struct SavedWordsView: View {
    let words: [SavedWord]
    let onCorrect: (SavedWord.ID, String) -> Void

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
                            SavedWordRow(word: word, onCorrect: onCorrect)
                        }
                    }
                }
            }

            Text("Misheard? Click a word to fix it. Translations are filled in by MajorTom afterwards.")
                .font(.rounded(11))
                .foregroundStyle(Palette.tertiary)
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.raised)
    }
}

private struct SavedWordRow: View {
    let word: SavedWord
    let onCorrect: (SavedWord.ID, String) -> Void
    @State private var editing: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("", text: Binding(get: { editing ?? word.word }, set: { editing = $0 }))
                .textFieldStyle(.plain)
                .font(.rounded(16, .heavy))
                .onSubmit {
                    if let editing { onCorrect(word.id, editing) }
                    editing = nil
                }
            Text(word.sentence)
                .font(.rounded(12))
                .foregroundStyle(Palette.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
