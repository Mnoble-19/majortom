import MajorTomStyle
import SwiftUI

/// One show, call or book: what was saved from it.
struct SourceDetailView: View {
    @EnvironmentObject private var store: Store
    let source: Source
    @State private var reviewing = false
    @State private var deleting = false
    @State private var renaming = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let items = store.items(in: source)
        // The route carries the source as it was when opened; counts come from
        // the live copy so they move as words are learned or deleted.
        let live = store.sources.first { $0.id == source.id } ?? source

        WordBrowser(items: items) {
            VStack(alignment: .leading, spacing: 16) {
                BackButton()
                header(live)
            }
        }
            .navigationTitle(live.title)
            .sheet(isPresented: $reviewing) {
                ReviewView(source: live) { reviewing = false }
                    .frame(minWidth: 760, minHeight: 640)
            }
            .confirmDeleting(live, isPresented: $deleting) { dismiss() }
            .renaming(live, isPresented: $renaming)
    }

    private func header(_ source: Source) -> some View {
        let due = store.dueItems(in: source, limit: 100).count

        return HStack(alignment: .center, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text(subtitle(source)).font(.rounded(15, .semibold)).opacity(0.8)
                Text(source.title)
                    .font(.rounded(32, .heavy))
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            Spacer()
            ZStack {
                Ring(progress: source.progress, color: Palette.good, lineWidth: 9)
                Text("\(source.learnedCount)/\(source.itemCount)")
                    .font(.rounded(14, .heavy))
                    .monospacedDigit()
            }
            .frame(width: 76, height: 76)
            .help("\(source.learnedCount) of \(source.itemCount) learned")

            VStack(alignment: .trailing, spacing: 10) {
                if due > 0 {
                    Button("Review \(due)") { reviewing = true }
                        .buttonStyle(ProminentButtonStyle(fill: source.kind.tint.ink, ink: source.kind.tint.fill))
                }
                TranslateButton(scope: .source(source))
                HStack(spacing: 14) {
                    Button { renaming = true } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button { deleting = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .font(.rounded(13, .semibold))
                .buttonStyle(.plain)
                .opacity(0.8)
            }
        }
        .foregroundStyle(source.kind.tint.ink)
        .padding(26)
        .background(source.kind.tint.fill, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private func subtitle(_ source: Source) -> String {
        switch source.kind {
        case .show: return "\(Platform.displayName(for: source.site)) · \(source.lastSavedAt.relativeDay)"
        case .call: return "With \(source.site) · \(source.createdAt.relativeDay)"
        case .book: return source.site.isEmpty ? "Book" : source.site
        case .own: return "Typed in by you"
        }
    }
}

/// Words you typed in yourself, and the place to type more.
struct MyWordsView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var translations: Translations

    @State private var text = ""
    @State private var meaning = ""
    @State private var sentence = ""
    @FocusState private var focused: Field?

    private enum Field { case text, meaning, sentence }

    var body: some View {
        let items = store.sources(of: .own).first.map(store.items(in:)) ?? []

        WordBrowser(items: items) {
            VStack(alignment: .leading, spacing: 20) {
                PageTitle(title: "My words",
                          subtitle: "Words you want to learn that you did not meet in a show, call or book.")
                form
            }
        }
        .navigationTitle("My words")
        .onAppear { focused = .text }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Word or phrase", text: $text)
                .font(.rounded(26, .heavy))
                .focused($focused, equals: .text)
                .onSubmit { focused = .meaning }
            TextField("Meaning — leave empty and MajorTom fills it in", text: $meaning)
                .font(.rounded(17))
                .focused($focused, equals: .meaning)
                .onSubmit { focused = .sentence }
            TextField("A sentence with it, if you have one", text: $sentence)
                .font(.rounded(17))
                .focused($focused, equals: .sentence)
                .onSubmit(add)
            HStack {
                Text("Return moves to the next field, and adds from the last.")
                    .font(.rounded(12))
                    .foregroundStyle(Palette.tertiary)
                Spacer()
                Button("Add word", action: add)
                    .buttonStyle(ProminentButtonStyle())
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .textFieldStyle(.plain)
        .card(padding: 24, radius: 26)
    }

    private func add() {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        let gloss = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        store.addOwnWord(word, translation: gloss,
                         context: sentence.trimmingCharacters(in: .whitespacesAndNewlines))
        if gloss.isEmpty { translations.translateWaiting(in: .kind(.own)) }
        text = ""
        meaning = ""
        sentence = ""
        focused = .text
    }
}
