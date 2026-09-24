import CallCore
import MajorTomStyle
import SwiftUI

/// A page of saved words: whatever header the caller gives it, filters, a
/// grid, and a detail panel. Used for one source and for the whole library.
struct WordBrowser<Header: View>: View {
    @EnvironmentObject private var store: Store
    let items: [Item]
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
                            WordCard(item: item, selected: item.id == selection)
                                .onTapGesture { selection = item.id == selection ? nil : item.id }
                                .contextMenu {
                                    Button(item.status == .learned ? "Move back to learning" : "Mark as learned") {
                                        store.setLearned(item, item.status != .learned)
                                    }
                                    Button(item.starred ? "Unstar" : "Star") { store.toggleStar(item) }
                                    Divider()
                                    Button("Delete…", role: .destructive) { confirmingRemoval = item }
                                }
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
                WordInspector(item: item, onClose: { selection = nil }) { confirmingRemoval = item }
                    .id(item.id)
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

            if let tag = item.positionLabel {
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
    @EnvironmentObject private var translations: Translations
    let item: Item
    let onClose: () -> Void
    let onRemove: () -> Void

    @State private var meaning = ""
    @FocusState private var editingMeaning: Bool
    @State private var checking = false
    @State private var suggestion: Gloss?
    @State private var checkFailed: String?
    @State private var editingContext = false
    @State private var context = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    Text(item.text)
                        .font(.rounded(32, .heavy))
                        .textSelection(.enabled)
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
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Palette.secondary)
                            .frame(width: 36, height: 36)
                            .background(Palette.raised, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }

                meaningSection

                if !item.alternatives.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Also said").font(.rounded(13, .bold)).foregroundStyle(Palette.secondary)
                        FlowLayout(spacing: 8, lineSpacing: 8) {
                            ForEach(item.alternatives, id: \.self) { word in
                                Text(word)
                                    .font(.rounded(15, .semibold))
                                    .padding(.horizontal, 12)
                                    .frame(height: 32)
                                    .background(Palette.raised, in: Capsule())
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }

                if !item.context.isEmpty || editingContext {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("In context").font(.rounded(13, .bold)).foregroundStyle(Palette.secondary)
                            Spacer()
                            Button(editingContext ? "Done" : "Edit") {
                                if editingContext { store.setContext(item, context.trimmingCharacters(in: .whitespacesAndNewlines)) }
                                else { context = item.context }
                                editingContext.toggle()
                            }
                            .buttonStyle(.plain)
                            .font(.rounded(13, .semibold))
                            .foregroundStyle(Palette.accentText)
                        }
                        if editingContext {
                            TextField("Sentence", text: $context, axis: .vertical)
                                .textFieldStyle(.plain)
                                .font(.rounded(17))
                                .lineLimit(2...10)
                                .padding(12)
                                .background(Palette.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        } else {
                            ContextSentence(sentence: item.context, word: item.text, size: 18)
                        }
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
        .onAppear { meaning = item.translation }
        .onChange(of: item.translation) { _, new in
            if !editingMeaning { meaning = new }
        }
        .onChange(of: editingMeaning) { _, editing in
            if !editing { saveMeaning() }
        }
    }

    /// Typed in by you — what the other person told you, say — or filled in by
    /// a translator. Either way it can be checked against the model.
    private var meaningSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Meaning").font(.rounded(13, .bold)).foregroundStyle(Palette.secondary)
            TextField("Type it, or ask the model", text: $meaning, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.rounded(19, .semibold))
                .foregroundStyle(Palette.accentText)
                .padding(12)
                .background(Palette.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .focused($editingMeaning)
                .onSubmit(saveMeaning)

            if let suggestion {
                SuggestionCard(gloss: suggestion, agrees: agrees(suggestion)) {
                    store.applyTranslation(suggestion.meaning, sentence: suggestion.sentence,
                                           alternatives: suggestion.alternatives, to: item)
                    meaning = suggestion.meaning
                    self.suggestion = nil
                } onKeep: {
                    // Keep your meaning, but take the extras the model offered.
                    store.applyTranslation(item.translation, sentence: suggestion.sentence,
                                           alternatives: suggestion.alternatives, to: item)
                    self.suggestion = nil
                }
            }

            HStack(spacing: 10) {
                Button(action: check) {
                    HStack(spacing: 6) {
                        if checking { ProgressView().controlSize(.small) }
                        Text(item.translation.isEmpty ? "Ask the model" : "Check with the model")
                    }
                }
                .buttonStyle(ProminentButtonStyle(fill: Palette.accentSoft, ink: Palette.accentText))
                .disabled(checking)
                if let checkFailed {
                    Text(checkFailed)
                        .font(.rounded(12))
                        .foregroundStyle(Palette.warmText)
                        .lineLimit(3)
                }
            }
        }
    }

    private func saveMeaning() {
        let trimmed = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != item.translation else { return }
        store.setMeaning(item, trimmed)
    }

    private func agrees(_ gloss: Gloss) -> Bool {
        gloss.meaning.localizedCaseInsensitiveCompare(item.translation) == .orderedSame
    }

    private func check() {
        saveMeaning()
        checking = true
        checkFailed = nil
        suggestion = nil
        Task {
            defer { checking = false }
            do {
                let gloss = try await translations.check(item)
                if item.translation.isEmpty {
                    // Nothing of yours to compare against: take it.
                    store.applyTranslation(gloss.meaning, sentence: gloss.sentence,
                                           alternatives: gloss.alternatives, to: item)
                    meaning = gloss.meaning
                } else {
                    suggestion = gloss
                }
            } catch {
                checkFailed = "\(error)"
            }
        }
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

/// What the model says, set against the meaning already there.
private struct SuggestionCard: View {
    let gloss: Gloss
    let agrees: Bool
    let onUse: () -> Void
    let onKeep: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(agrees ? "The model agrees" : "The model says")
                .font(.rounded(12, .bold))
                .foregroundStyle(agrees ? Palette.goodText : Palette.secondary)
            if !agrees {
                Text(gloss.meaning).font(.rounded(17, .bold))
            }
            if !gloss.sentence.isEmpty {
                Text(gloss.sentence).font(.rounded(13)).foregroundStyle(Palette.secondary)
            }
            HStack(spacing: 10) {
                if !agrees {
                    Button("Use this", action: onUse)
                        .buttonStyle(ProminentButtonStyle(fill: Palette.accent, ink: .white))
                }
                Button(agrees ? "Done" : "Keep mine", action: onKeep)
                    .buttonStyle(ProminentButtonStyle(fill: Palette.raised, ink: Palette.text))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.accentSoft.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
