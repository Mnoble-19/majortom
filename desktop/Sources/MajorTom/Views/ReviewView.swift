import MajorTomStyle
import SwiftUI

/// One sitting of review: the sentence first, the meaning on request, then
/// "Not yet" or "Got it". A "Not yet" comes back at the end of the same sitting.
struct ReviewView: View {
    @EnvironmentObject private var store: Store
    /// Review one source only, or everything that is due.
    let source: Source?
    let onDone: () -> Void

    @State private var queue: [Item] = []
    @State private var total = 0
    @State private var revealed = false
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 0) {
            if !loaded {
                Color.clear
            } else if let item = queue.first {
                progress
                Spacer(minLength: 20)
                card(item)
                Spacer(minLength: 20)
                controls(item)
            } else {
                finished
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.accentSoft.opacity(0.5))
        .background(Palette.background)
        .navigationTitle(source.map { "Review · \($0.title)" } ?? "Review")
        .onAppear(perform: load)
    }

    private func load() {
        queue = store.dueItems(in: source)
        total = queue.count
        revealed = false
        loaded = true
    }

    private var progress: some View {
        HStack(spacing: 14) {
            ProgressView(value: Double(total - queue.count), total: Double(max(total, 1)))
                .progressViewStyle(.linear)
                .tint(Palette.accent)
            Text("\(total - queue.count)/\(total)")
                .font(.rounded(15, .heavy))
                .foregroundStyle(Palette.accentText)
                .monospacedDigit()
            Button("Stop", action: onDone)
                .buttonStyle(.plain)
                .font(.rounded(14, .semibold))
                .foregroundStyle(Palette.secondary)
                .keyboardShortcut(.cancelAction)
                .help("Stop reviewing; answers so far are kept")
        }
        .frame(maxWidth: 640)
    }

    private func card(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(sourceLine(item), systemImage: item.sourceKind.icon)
                    .font(.rounded(13, .bold))
                    .foregroundStyle(item.sourceKind.tint.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(item.sourceKind.tint.fill, in: Capsule())
                Spacer()
                if item.starred {
                    Image(systemName: "star.fill").foregroundStyle(Palette.warm)
                }
            }

            Text(item.text)
                .font(.rounded(52, .heavy))
                .minimumScaleFactor(0.5)
                .lineLimit(2)

            if !item.context.isEmpty {
                ContextSentence(sentence: item.context, word: item.text, size: 21)
            }

            Spacer(minLength: 0)

            if revealed {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.translation)
                        .font(.rounded(28, .heavy))
                        .foregroundStyle(Palette.accentText)
                    if !item.contextTranslation.isEmpty {
                        Text(item.contextTranslation)
                            .font(.rounded(16))
                            .foregroundStyle(Palette.secondary)
                    }
                }
                .padding(.top, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) {
                    Rectangle().fill(Palette.hairline).frame(height: 1)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(36)
        .frame(maxWidth: 640, minHeight: 380, alignment: .topLeading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 24, y: 12)
        .animation(.spring(duration: 0.3), value: revealed)
        .id(item.id)
    }

    @ViewBuilder
    private func controls(_ item: Item) -> some View {
        HStack(spacing: 16) {
            if revealed {
                Button { answer(item, correct: false) } label: {
                    Label("Not yet", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(ProminentButtonStyle(fill: Palette.card, ink: Palette.badText))
                .keyboardShortcut("1", modifiers: [])

                Button { answer(item, correct: true) } label: {
                    Label("Got it", systemImage: "checkmark")
                }
                .buttonStyle(ProminentButtonStyle(fill: Palette.good, ink: .white))
                .keyboardShortcut("2", modifiers: [])
            } else {
                Button("Show meaning") { revealed = true }
                    .buttonStyle(ProminentButtonStyle())
                    .keyboardShortcut(.space, modifiers: [])
            }
        }
        .frame(height: 50)
        Text(revealed ? "Press 1 or 2" : "Press Space")
            .font(.rounded(12, .semibold))
            .foregroundStyle(Palette.tertiary)
            .padding(.top, 10)
    }

    private var finished: some View {
        VStack(spacing: 16) {
            Image(systemName: total > 0 ? "checkmark.seal.fill" : "cup.and.saucer.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(total > 0 ? Palette.good : Palette.accent)
                .frame(width: 96, height: 96)
                .background(total > 0 ? Palette.goodSoft : Palette.accentSoft, in: Circle())
            Text(total > 0 ? "Done for now" : "Nothing to review")
                .font(.rounded(28, .heavy))
            Text(total > 0
                 ? "You went through \(total) \(total == 1 ? "word" : "words"). The ones you got come back in a few days."
                 : "Words turn up here once they have a translation and are due again.")
                .font(.rounded(15))
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button("Back", action: onDone)
                .buttonStyle(ProminentButtonStyle())
                .keyboardShortcut(.defaultAction)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func answer(_ item: Item, correct: Bool) {
        store.recordReview(item, correct: correct)
        withAnimation(.spring(duration: 0.3)) {
            queue.removeFirst()
            if !correct { queue.append(item) }
            revealed = false
        }
    }

    private func sourceLine(_ item: Item) -> String {
        [item.sourceTitle, item.positionLabel].compactMap { $0 }.joined(separator: " · ")
    }
}

/// A sentence with the saved word marked in it. Matching ignores case and
/// punctuation, so "Ahnung," still lights up for a saved "Ahnung"; each word of
/// a saved phrase is marked on its own.
struct ContextSentence: View {
    let sentence: String
    let word: String
    var size: CGFloat = 17

    var body: some View {
        FlowLayout(spacing: 5, lineSpacing: 6) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                Text(token.text)
                    .font(.rounded(size, token.isMatch ? .bold : .regular))
                    .highlighted(token.isMatch)
            }
        }
    }

    private var tokens: [(text: String, isMatch: Bool)] {
        let targets = Set(word.lowercased().split(separator: " ").map(String.init))
        return sentence.split(separator: " ").map { raw in
            let bare = raw.trimmingCharacters(in: .punctuationCharacters).lowercased()
            return (String(raw), targets.contains(bare))
        }
    }
}
