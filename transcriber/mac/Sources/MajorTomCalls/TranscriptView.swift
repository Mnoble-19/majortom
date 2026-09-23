import CallCore
import SwiftUI

/// Wraps its children onto as many rows as it takes. Needed because each word
/// has to be its own tappable view, so the transcript cannot just be a `Text`.
struct WordFlow: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// One committed line of speech. Every word is clickable.
struct LineView: View {
    let line: Line
    let person: String
    let savedWords: Set<String>
    let onTap: (String) -> Void

    private var isMine: Bool { line.speaker == .me }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(isMine ? "you" : person)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(isMine ? .tertiary : .secondary)
                Text(timestamp)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.quaternary)
            }

            WordFlow {
                ForEach(Array(line.text.split(separator: " ").enumerated()), id: \.offset) { _, token in
                    let word = String(token)
                    WordButton(
                        word: word,
                        isSaved: savedWords.contains(Self.bare(word).lowercased()),
                        action: { onTap(word) })
                }
            }
        }
        .padding(.vertical, 5)
        .opacity(isMine ? 0.6 : 1)
    }

    private var timestamp: String {
        let total = Int(line.start)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func bare(_ word: String) -> String {
        word.trimmingCharacters(in: CharacterSet.punctuationCharacters)
    }
}

private struct WordButton: View {
    let word: String
    let isSaved: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Text(word)
            .font(.system(size: 15))
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSaved ? Color.accentColor.opacity(0.22)
                          : hovering ? Color.primary.opacity(0.09) : .clear))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
    }
}

/// The words saved during this session, each filling in as its translation
/// arrives. Editable, so a misheard word can be corrected on the spot.
struct SavedWordsView: View {
    let words: [SavedWord]
    let onCorrect: (SavedWord.ID, String) -> Void

    var body: some View {
        if words.isEmpty {
            VStack(spacing: 4) {
                Text("No words yet").foregroundStyle(.secondary).font(.callout)
                Text("Click any word in the transcript")
                    .foregroundStyle(.tertiary).font(.caption)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(words.reversed()) { word in
                        SavedWordRow(word: word, onCorrect: onCorrect)
                    }
                }
                .padding(12)
            }
        }
    }
}

private struct SavedWordRow: View {
    let word: SavedWord
    let onCorrect: (SavedWord.ID, String) -> Void
    @State private var editing: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                TextField("", text: Binding(
                    get: { editing ?? word.word },
                    set: { editing = $0 }))
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .onSubmit {
                        if let editing { onCorrect(word.id, editing) }
                        editing = nil
                    }

                switch word.state {
                case .translating:
                    ProgressView().controlSize(.small)
                case .done:
                    EmptyView()
                case .failed:
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange).font(.caption)
                }
            }

            if let gloss = word.gloss {
                Text(gloss.meaning)
                    .font(.system(size: 13))
                    .foregroundStyle(word.state == .done ? .primary : .secondary)
                if gloss.dictionaryForm.lowercased() != word.word.lowercased() {
                    Text(gloss.dictionaryForm)
                        .font(.caption).foregroundStyle(.tertiary)
                }
                Text(gloss.sentence)
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.top, 1)
            } else if case .failed(let reason) = word.state {
                Text(reason).font(.caption).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
