import CallCore
import MajorTomStyle
import SwiftUI

/// Set up a conversation, then the live screen: lines scrolling, tap a word to
/// keep it.
struct TalkView: View {
    let session: PhoneSession
    let pending: PendingWords

    var body: some View {
        Group {
            if session.isRunning {
                LiveView(session: session, pending: pending)
            } else {
                SetupView(session: session, pending: pending)
            }
        }
        .background(Palette.background)
        .task { await session.prepareModel() }
    }
}

private struct SetupView: View {
    let session: PhoneSession
    let pending: PendingWords
    @FocusState private var nameFocused: Bool

    /// People you have talked to before, so the next chat with them is a tap.
    private var recentPeople: [String] {
        let typed = session.person.trimmingCharacters(in: .whitespaces)
        return PhoneSession.recentPeople.filter { $0.caseInsensitiveCompare(typed) != .orderedSame }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Who are you talking to?")
                        .font(.rounded(14, .semibold))
                        .foregroundStyle(Palette.secondary)
                    TextField("Name", text: Binding(get: { session.person }, set: { session.person = $0 }))
                        .font(.rounded(30, .heavy))
                        .textInputAutocapitalization(.words)
                        .submitLabel(.go)
                        .focused($nameFocused)
                        .onSubmit(start)
                    if !recentPeople.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(recentPeople.prefix(3), id: \.self) { name in
                                Button(name) { session.person = name }
                                    .font(.rounded(15, .semibold))
                                    .padding(.horizontal, 14)
                                    .frame(height: 34)
                                    .background(Palette.raised, in: Capsule())
                                    .foregroundStyle(Palette.text)
                            }
                        }
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Spoken in").font(.rounded(14, .semibold)).foregroundStyle(Palette.secondary)
                    Picker("Spoken in", selection: Binding(
                        get: { session.localeIdentifier }, set: { session.localeIdentifier = $0 })) {
                        Text("Germany").tag("de-DE")
                        Text("Austria").tag("de-AT")
                        Text("Switzerland").tag("de-CH")
                    }
                    .pickerStyle(.segmented)
                }
                .card()

                modelStatus
                    .font(.rounded(15, .semibold))
                    .padding(.horizontal, 6)

                if let error = session.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.rounded(15, .medium))
                        .foregroundStyle(Palette.warmText)
                        .padding(.horizontal, 6)
                }
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Text("Words are kept with their sentence and translated on your Mac. The recording isn’t kept.")
                    .font(.rounded(13))
                    .foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center)
                Button(action: start) {
                    Label("Start listening", systemImage: "waveform")
                        .font(.rounded(18, .bold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(session.person.trimmingCharacters(in: .whitespaces).isEmpty
                          || session.modelState != .ready)
            }
            .padding(20)
            .background(Palette.background)
        }
        .navigationTitle("New conversation")
        .onChange(of: session.localeIdentifier) { _, _ in
            Task { await session.prepareModel() }
        }
    }

    @ViewBuilder
    private var modelStatus: some View {
        switch session.modelState {
        case .downloading:
            HStack(spacing: 10) {
                ProgressView()
                Text("Getting the German speech model…").foregroundStyle(Palette.secondary)
            }
        case .ready:
            Label(session.engine == .speechTranscriber
                  ? "German speech model ready"
                  : "Ready, using system dictation on this iPhone",
                  systemImage: "checkmark.circle.fill")
                .foregroundStyle(Palette.goodText)
        case .unsupported(let why):
            Label(why, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.warmText)
        case .unknown:
            EmptyView()
        }
    }

    private func start() {
        nameFocused = false
        Task { await session.start() }
    }
}

private struct LiveView: View {
    let session: PhoneSession
    let pending: PendingWords
    @State private var justSaved: String?
    @State private var toastTask: Task<Void, Never>?
    private var saved: [SyncPayload.Word] {
        pending.sessions.first { $0.id == session.sessionID }?.words ?? []
    }

    /// Every word of every saved word or phrase, for highlighting.
    private var savedWords: Set<String> {
        Set(saved.flatMap { $0.text.lowercased().split(separator: " ").map(String.init) })
    }

    var body: some View {
        FollowingScrollView(following: "\(session.lines.count) \(session.volatile)") {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(session.lines) { line in
                    LineCard(line: line, savedWords: savedWords) { text in
                        save(text, from: line)
                    }
                    .id(line.id)
                }
                if !session.volatile.isEmpty {
                    Text(session.volatile)
                        .font(.rounded(21))
                        .foregroundStyle(Palette.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card(padding: 16, radius: 22)
                        .opacity(0.7)
                }
                if session.lines.isEmpty && session.volatile.isEmpty {
                    Text("Listening… lines appear here as people speak.")
                        .font(.rounded(16))
                        .foregroundStyle(Palette.secondary)
                        .padding(.top, 40)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(16)
        }
        .overlay(alignment: .bottom) { toast }
        .safeAreaInset(edge: .bottom) { controls }
        .toolbar {
            ToolbarItem(placement: .principal) { header }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Avatar(name: session.person, size: 32)
            VStack(alignment: .leading, spacing: 0) {
                Text(session.person).font(.rounded(16, .heavy))
                TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                    Text("Listening · " + Duration.seconds(context.date.timeIntervalSince(session.startedAt))
                        .formatted(.time(pattern: .minuteSecond)))
                        .font(.rounded(12, .medium))
                        .foregroundStyle(Palette.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    @ViewBuilder
    private var toast: some View {
        if let word = justSaved {
            HStack(spacing: 10) {
                Image(systemName: "checkmark").foregroundStyle(Palette.good)
                Text("Saved “\(word)”")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Undo") {
                    pending.remove(word, from: session.sessionID)
                    withAnimation { justSaved = nil }
                }
                .foregroundStyle(Palette.accentSoft)
                .fontWeight(.heavy)
            }
            .font(.rounded(15, .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 44)
            .background(.black.opacity(0.85), in: Capsule())
            .padding(.bottom, 130)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var controls: some View {
        HStack {
            Text("\(saved.count) saved")
                .font(.rounded(15, .heavy))
                .foregroundStyle(Palette.onHighlight)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Palette.highlight, in: Capsule())
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Task { await session.stop() }
            } label: {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white)
                    .frame(width: 26, height: 26)
                    .frame(width: 76, height: 76)
                    .background(Palette.bad, in: Circle())
                    .padding(6)
                    .background(Palette.bad.opacity(0.18), in: Circle())
            }
            .accessibilityLabel("Stop listening")
            Text("Tap a word to keep it.\nHold for its sentence,\nslide for a phrase.")
                .font(.rounded(13, .medium))
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Palette.background)
    }

    private func save(_ word: String, from line: Line) {
        guard !word.isEmpty else { return }
        pending.add(
            .init(text: word, sentence: line.sentence(containing: word), position: line.start),
            to: session.sessionID, person: session.person, startedAt: session.startedAt)
        withAnimation(.spring(duration: 0.3)) { justSaved = word }
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation { justSaved = nil }
        }
    }
}

/// One line of the transcript. Tap a word to keep it; hold to keep the whole
/// sentence it sits in; hold and slide to keep just the words you slide over.
///
/// The gestures live on the card rather than on each word so that a slide can
/// cross from word to word, which per-word gestures cannot do.
private struct LineCard: View {
    let line: Line
    let savedWords: Set<String>
    let onSave: (String) -> Void

    /// Where each word sits on the card, for turning a touch into a word.
    @State private var frames: [Int: CGRect] = [:]
    /// The word the hold began on and the one the finger is over now.
    @State private var selection: (anchor: Int, current: Int)?

    private var tokens: [String] { line.text.split(separator: " ").map(String.init) }
    private let space = "line"

    var body: some View {
        FlowLayout(spacing: 4, lineSpacing: 6) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                word(token, at: index)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: {
                        frames[index] = $0
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16, radius: 22)
        .coordinateSpace(.named(space))
        .contentShape(Rectangle())
        .gesture(hold.exclusively(before: tap))
    }

    private func word(_ text: String, at index: Int) -> some View {
        let isSaved = savedWords.contains(Self.clean(text).lowercased())
        let isSelected = selection.map { min($0.anchor, $0.current)...max($0.anchor, $0.current) }?
            .contains(index) ?? false
        return Text(text)
            .font(.rounded(21, isSaved ? .bold : .regular))
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .highlighted(isSaved)
            .background(isSelected ? Palette.accent.opacity(0.25) : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var tap: some Gesture {
        SpatialTapGesture(coordinateSpace: .named(space)).onEnded { value in
            guard let index = index(at: value.location) else { return }
            onSave(Self.clean(tokens[index]))
        }
    }

    /// A hold, then optionally a slide. Letting go without sliding keeps the
    /// sentence; sliding keeps the words between where it began and ended.
    private var hold: some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(space)))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                guard let drag else {
                    if selection == nil { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                    return
                }
                guard let index = nearestIndex(to: drag.location) else { return }
                if let current = selection {
                    if current.current != index {
                        selection = (current.anchor, index)
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                } else {
                    let start = nearestIndex(to: drag.startLocation) ?? index
                    selection = (start, index)
                }
            }
            .onEnded { value in
                defer { selection = nil }
                guard case .second(true, let drag) = value else { return }
                let moved = drag.map { hypot($0.translation.width, $0.translation.height) > 12 } ?? false
                if moved, let selection {
                    let range = min(selection.anchor, selection.current)...max(selection.anchor, selection.current)
                    onSave(Self.clean(tokens[range].joined(separator: " ")))
                } else {
                    let anchor = selection?.anchor ?? drag.flatMap { nearestIndex(to: $0.startLocation) }
                    onSave(sentence(around: anchor))
                }
            }
    }

    /// The word under a point, if the point is on one.
    private func index(at point: CGPoint) -> Int? {
        frames.first { $0.value.insetBy(dx: -2, dy: -3).contains(point) }?.key
    }

    /// The word under a point, or the closest one on the same row — a slide
    /// passes through the gaps between words and past the end of a row.
    private func nearestIndex(to point: CGPoint) -> Int? {
        if let hit = index(at: point) { return hit }
        let row = frames.filter { $0.value.minY - 3 <= point.y && point.y <= $0.value.maxY + 3 }
        let pool = row.isEmpty ? frames : row
        return pool.min { distance($0.value, point) < distance($1.value, point) }?.key
    }

    private func distance(_ rect: CGRect, _ point: CGPoint) -> CGFloat {
        hypot(max(rect.minX - point.x, 0, point.x - rect.maxX),
              max(rect.minY - point.y, 0, point.y - rect.maxY))
    }

    /// The sentence holding word `index`, or the whole line when the hold
    /// started off any word or the line is one sentence anyway.
    private func sentence(around index: Int?) -> String {
        let text = line.text
        guard let index else { return text.trimmingCharacters(in: .whitespaces) }
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { substring, _, _, _ in
            let trimmed = substring?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { sentences.append(trimmed) }
        }
        var start = 0
        for sentence in sentences {
            let count = sentence.split(separator: " ").count
            if index < start + count { return sentence }
            start += count
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// Trims the punctuation a transcript leaves on the ends — "Ahnung," — but
    /// keeps what sits inside a phrase.
    static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
    }
}
