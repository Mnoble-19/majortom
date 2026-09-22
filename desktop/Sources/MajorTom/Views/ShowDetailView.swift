import SwiftUI

struct ShowDetailView: View {
    @EnvironmentObject private var store: Store
    let source: Source

    @State private var kind: ItemKind = .word
    @State private var search = ""
    @State private var sortOrder = [KeyPathComparator(\Item.position)]

    private var rows: [Item] {
        let all = store.items(for: source, kind: kind)
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = needle.isEmpty ? all : all.filter {
            $0.text.lowercased().contains(needle)
                || $0.translation.lowercased().contains(needle)
        }
        return filtered.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.border)
            table
        }
        .background(Theme.bg)
        .navigationTitle(source.title)
        .searchable(text: $search, placement: .toolbar, prompt: "Filter")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(source.title)
                    .font(Theme.serif(30, .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                Spacer(minLength: 16)
                if let url = URL(string: source.url), !source.url.isEmpty {
                    Link(destination: url) {
                        Label("Open", systemImage: "arrow.up.right.square")
                            .font(Theme.ui(14))
                    }
                    .foregroundStyle(Theme.muted)
                }
            }

            if !source.site.isEmpty {
                Text(Platform.displayName(for: source.site)).pill(Theme.secondary)
            }

            Picker("", selection: $kind) {
                Text("Words (\(source.wordCount))").tag(ItemKind.word)
                Text("Phrases (\(source.phraseCount))").tag(ItemKind.phrase)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .font(Theme.ui(15))
            .frame(width: 330)
        }
        .padding(.horizontal, 30)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private var table: some View {
        let items = rows
        if items.isEmpty {
            EmptyState(
                icon: kind == .word ? "character.book.closed" : "text.quote",
                title: search.isEmpty ? "No \(kind == .word ? "words" : "phrases") saved" : "No matches",
                message: search.isEmpty && kind == .phrase
                    ? "Phrase capture is not wired up in the extension yet."
                    : ""
            )
        } else {
            Table(items, sortOrder: $sortOrder) {
                TableColumn("") { item in
                    StarButton(starred: item.starred) { store.toggleStar(item) }
                        .padding(.vertical, 9)
                }
                .width(30)

                TableColumn(kind == .word ? "Word" : "Phrase", value: \.text) { item in
                    Text(item.text)
                        .font(Theme.serif(17, .medium))
                        .foregroundStyle(Theme.accent)
                        .padding(.vertical, 9)
                }
                .width(min: 150, ideal: 220)

                TableColumn("Translation", value: \.translation) { item in
                    Text(item.translation)
                        .font(Theme.ui(16))
                        .foregroundStyle(Theme.secondary)
                        .padding(.vertical, 9)
                }
                .width(min: 150, ideal: 240)

                TableColumn("Context", value: \.context) { item in
                    Text(item.context)
                        .font(Theme.ui(15))
                        .foregroundStyle(Theme.muted)
                        .help(item.contextTranslation)
                        .padding(.vertical, 9)
                }

                TableColumn("At", value: \.position) { item in
                    Text(timecode(item.position))
                        .font(Theme.mono(14))
                        .foregroundStyle(Theme.faint)
                        .padding(.vertical, 9)
                }
                .width(70)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
        }
    }

    private func timecode(_ seconds: Double) -> String {
        guard seconds > 0 else { return "—" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
