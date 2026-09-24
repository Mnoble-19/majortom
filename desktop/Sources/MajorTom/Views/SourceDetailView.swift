import SwiftUI

struct SourceDetailView: View {
    @EnvironmentObject private var store: Store
    let source: Source

    @State private var kind: ItemKind = .word
    @State private var search = ""
    @State private var filter: ItemStatus?
    @State private var sortOrder = [KeyPathComparator(\Item.position)]

    private var all: [Item] { store.items(for: source, kind: kind) }

    private var rows: [Item] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        return all
            .filter { filter == nil || $0.status == filter }
            .filter {
                needle.isEmpty
                    || $0.text.lowercased().contains(needle)
                    || $0.translation.lowercased().contains(needle)
            }
            .sorted(using: sortOrder)
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
                Text(source.kind == .book ? source.site : Platform.displayName(for: source.site))
                    .pill(Theme.secondary)
            }

            HStack(spacing: 16) {
                Picker("", selection: $kind) {
                    Text("Words (\(source.wordCount))").tag(ItemKind.word)
                    Text("Phrases (\(source.phraseCount))").tag(ItemKind.phrase)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .font(Theme.ui(15))
                .frame(width: 330)

                Picker("", selection: $filter) {
                    Text("All").tag(ItemStatus?.none)
                    Text(ItemStatus.learning.label).tag(ItemStatus?.some(.learning))
                    Text(ItemStatus.learned.label).tag(ItemStatus?.some(.learned))
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .font(Theme.ui(14))
                .frame(width: 130)

                Spacer()

                if learned > 0 {
                    Text("\(learned) of \(all.count) learned")
                        .font(Theme.ui(13))
                        .foregroundStyle(Theme.success)
                }
            }
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
                title: search.isEmpty && filter == nil
                    ? "No \(kind == .word ? "words" : "phrases") saved"
                    : "No matches",
                message: search.isEmpty && filter == nil && kind == .phrase && source.kind == .show
                    ? "Phrase capture is not wired up in the extension yet."
                    : ""
            )
        } else {
            Table(items, sortOrder: $sortOrder) {
                TableColumn("") { item in
                    LearnedButton(status: item.status) { store.toggleLearned(item) }
                        .padding(.vertical, 9)
                }
                .width(30)

                TableColumn("") { item in
                    StarButton(starred: item.starred) { store.toggleStar(item) }
                        .padding(.vertical, 9)
                }
                .width(30)

                TableColumn(kind == .word ? "Word" : "Phrase", value: \.text) { item in
                    Text(item.text)
                        .font(Theme.serif(17, .medium))
                        .foregroundStyle(Theme.accent)
                        .strikethrough(item.status == .learned, color: Theme.faint)
                        .opacity(dim(item))
                        .padding(.vertical, 9)
                }
                .width(min: 150, ideal: 220)

                TableColumn("Translation", value: \.translation) { item in
                    Text(item.translation)
                        .font(Theme.ui(16))
                        .foregroundStyle(Theme.secondary)
                        .opacity(dim(item))
                        .padding(.vertical, 9)
                }
                .width(min: 150, ideal: 240)

                TableColumn("Context", value: \.context) { item in
                    Text(item.context)
                        .font(Theme.ui(15))
                        .foregroundStyle(Theme.muted)
                        .opacity(dim(item))
                        .help(item.contextTranslation)
                        .padding(.vertical, 9)
                }

                TableColumn(positionLabel, value: \.position) { item in
                    Text(position(item.position))
                        .font(Theme.mono(14))
                        .foregroundStyle(Theme.faint)
                        .opacity(dim(item))
                        .padding(.vertical, 9)
                }
                .width(70)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
        }
    }

    private var learned: Int { all.filter { $0.status == .learned }.count }

    /// Learned rows stay in the list but recede.
    private func dim(_ item: Item) -> Double {
        item.status == .learned ? 0.4 : 1
    }

    private var positionLabel: String {
        source.kind == .book ? "Page" : "At"
    }

    /// `position` is seconds into a video or call, but a page in a book, and
    /// rendering page 16 as "0:16" would be quietly wrong.
    private func position(_ value: Double) -> String {
        guard value > 0 else { return "—" }
        if source.kind == .book { return String(Int(value)) }
        let total = Int(value)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
