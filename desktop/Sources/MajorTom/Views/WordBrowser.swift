import MajorTomStyle
import SwiftUI

/// A page of saved words: whatever header the caller gives it, filters, a
/// grid, and a detail panel. Used for one source and for the whole library.
struct WordBrowser<Header: View>: View {
    @EnvironmentObject private var store: Store
    let items: [Item]
    var showsSource = false
    @ViewBuilder let header: () -> Header

    @State private var filter: Filter = .all
    @State private var search = ""
    @State private var selection: Item.ID?
    @State private var confirmingRemoval: Item?

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", learning = "To learn", learned = "Learned", phrases = "Phrases", starred = "Starred"
        var id: String { rawValue }

        func includes(_ item: Item) -> Bool {
            switch self {
            case .all: return true
            case .learning: return item.status == .learning
            case .learned: return item.status == .learned
            case .phrases: return item.kind == .phrase
            case .starred: return item.starred
            }
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 14)]

    private var shown: [Item] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        return items.filter { item in
            filter.includes(item) && (needle.isEmpty
                || item.text.lowercased().contains(needle)
                || item.translation.lowercased().contains(needle))
        }
    }

    private var selected: Item? {
        selection.flatMap { id in items.first { $0.id == id } }
    }

    var body: some View {
        let shown = shown

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header()
                    .padding(.bottom, 6)
                HStack(spacing: 8) {
                    ForEach(Filter.allCases.filter { $0 == .all || items.contains(where: $0.includes) }) { option in
                        Pill(text: label(option), selected: filter == option) { filter = option }
                    }
                }

                if shown.isEmpty {
                    Text(search.isEmpty ? "Nothing here yet." : "No matches for “\(search)”.")
                        .font(.rounded(15))
                        .foregroundStyle(Palette.secondary)
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(shown) { item in
                            WordCard(item: item, showsSource: showsSource, selected: item.id == selection)
                                .onTapGesture { selection = item.id == selection ? nil : item.id }
                        }
                    }
                }
            }
            .padding(32)
        }
        .background(Palette.background)
        .searchable(text: $search, placement: .toolbar, prompt: "Filter words")
        .onDeleteCommand { confirmingRemoval = selected }
        .inspector(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selection = nil } })) {
            if let item = selected {
                WordInspector(item: item) { confirmingRemoval = item }
                    .inspectorColumnWidth(min: 300, ideal: 340, max: 420)
            }
        }
        .confirmationDialog(
            "Delete “\(confirmingRemoval?.text ?? "")”?",
            isPresented: Binding(get: { confirmingRemoval != nil }, set: { if !$0 { confirmingRemoval = nil } })
        ) {
            Button("Delete", role: .destructive) {
                if let item = confirmingRemoval {
                    store.remove(item)
                    if selection == item.id { selection = nil }
                }
            }
        } message: {
            Text("It leaves the library for good, even if a browser sends it again.")
        }
    }

    private func label(_ option: Filter) -> String {
        let count = items.filter(option.includes).count
        return "\(option.rawValue) \(count)"
    }
}

private struct WordCard: View {
    let item: Item
    let showsSource: Bool
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Text(item.text)
                    .font(.rounded(20, .heavy))
                    .lineLimit(2)
                Spacer(minLength: 4)
                if item.starred {
                    Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(Palette.warm)
                }
                if item.status == .learned {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Palette.good)
                        .accessibilityLabel("Learned")
                }
            }
            Group {
                if item.translation.isEmpty {
                    Text("No translation yet").italic().foregroundStyle(Palette.tertiary)
                } else {
                    Text(item.translation).foregroundStyle(Palette.secondary)
                }
            }
            .font(.rounded(15))
            .lineLimit(2)

            Spacer(minLength: 8)

            if let tag = showsSource ? item.sourceTitle : item.positionLabel {
                Text(tag)
                    .font(.rounded(12, .bold))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Palette.raised, in: Capsule())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 136, alignment: .topLeading)
        .background(item.status == .learned ? Palette.goodSoft : Palette.card,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(selected ? Palette.accent : hovering ? Palette.hairline : .clear, lineWidth: selected ? 2.5 : 1.5))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

private struct WordInspector: View {
    @EnvironmentObject private var store: Store
    let item: Item
    let onRemove: () -> Void

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.text)
                                .font(.rounded(32, .heavy))
                                .textSelection(.enabled)
                            Text(item.translation.isEmpty ? "No translation yet" : item.translation)
                                .font(.rounded(19, .semibold))
                                .foregroundStyle(item.translation.isEmpty ? Palette.tertiary : Palette.accentText)
                        }
                        Spacer()
                        Button { store.toggleStar(item) } label: {
                            Image(systemName: item.starred ? "star.fill" : "star")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(item.starred ? Palette.warm : Palette.secondary)
                                .frame(width: 36, height: 36)
                                .background(Palette.raised, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.starred ? "Unstar" : "Star")
                    }

                    if !item.context.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("In context").font(.rounded(13, .bold)).foregroundStyle(Palette.secondary)
                            ContextSentence(sentence: item.context, word: item.text, size: 18)
                            if !item.contextTranslation.isEmpty {
                                Text(item.contextTranslation)
                                    .font(.rounded(15))
                                    .foregroundStyle(Palette.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        KindBadge(kind: item.sourceKind, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.sourceTitle).font(.rounded(14, .semibold)).lineLimit(2)
                            Text([item.positionLabel, "saved \(item.createdAt.relativeDay.lowercased())"]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.rounded(12))
                                .foregroundStyle(Palette.secondary)
                        }
                        Spacer()
                        if let url = watchURL {
                            Link(destination: url) { Image(systemName: "arrow.up.right") }
                                .help("Open where you saved it")
                        }
                    }

                    VStack(spacing: 10) {
                        Button(item.status == .learned ? "Move back to learning" : "Mark as learned") {
                            store.setLearned(item, item.status != .learned)
                        }
                        .buttonStyle(item.status == .learned
                                     ? ProminentButtonStyle(fill: Palette.raised, ink: Palette.text)
                                     : ProminentButtonStyle(fill: Palette.good, ink: .white))
                        .frame(maxWidth: .infinity)

                        Button("Delete word", role: .destructive, action: onRemove)
                            .buttonStyle(.plain)
                            .font(.rounded(14, .semibold))
                            .foregroundStyle(Palette.badText)
                    }
                }
                .padding(22)
        }
        .background(Palette.card)
    }

    /// The episode, jumping to the moment on YouTube, which takes a time in
    /// the URL; other sites just open the episode.
    private var watchURL: URL? {
        guard item.sourceKind == .show, var components = URLComponents(string: item.sourceURL),
                  components.scheme?.hasPrefix("http") == true else { return nil }
        if components.host?.contains("youtube") == true, item.position > 0 {
                components.queryItems = (components.queryItems ?? []).filter { $0.name != "t" }
                    + [URLQueryItem(name: "t", value: "\(Int(item.position))s")]
        }
        return components.url
    }
}
