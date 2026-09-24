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

    /// People already waiting to sync, so a second chat with the same person
    /// is one tap away.
    private var recentPeople: [String] {
        var seen = Set<String>()
        return pending.sessions.reversed()
            .filter { $0.id != PendingWords.ownSessionID }
            .map(\.person)
            .filter { seen.insert($0).inserted }
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
    /// Set by a long press: the first word of a phrase, waiting for a tap on
    /// its last word.
    @State private var phraseStart: (line: Line.ID, index: Int)?

    private var saved: [SyncPayload.Word] {
        pending.sessions.first { $0.id == session.sessionID }?.words ?? []
    }

    /// Every word of every saved word or phrase, for highlighting.
    private var savedWords: Set<String> {
        Set(saved.flatMap { $0.text.lowercased().split(separator: " ").map(String.init) })
    }

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(session.lines) { line in
                        FlowLayout(spacing: 4, lineSpacing: 6) {
                            ForEach(Array(line.text.split(separator: " ").enumerated()), id: \.offset) { index, token in
                                word(String(token), at: index, in: line)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card(padding: 16, radius: 22)
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
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(16)
            }
            .onChange(of: session.lines.count) { _, _ in
                withAnimation { scroll.scrollTo("bottom", anchor: .bottom) }
            }
        }
        .overlay(alignment: .bottom) { toast }
        .safeAreaInset(edge: .bottom) { controls }
        .toolbar {
            ToolbarItem(placement: .principal) { header }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func word(_ text: String, at index: Int, in line: Line) -> some View {
        let bare = Self.clean(text)
        let isSaved = savedWords.contains(bare.lowercased())
        let isStart = phraseStart?.line == line.id && phraseStart?.index == index
        return Text(text)
            .font(.rounded(21, isSaved ? .bold : .regular))
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .highlighted(isSaved)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isStart ? Palette.accent : .clear, lineWidth: 2))
            .contentShape(Rectangle())
            .onTapGesture { tap(index, in: line) }
            .onLongPressGesture(minimumDuration: 0.4) {
                phraseStart = (line.id, index)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
    }

    /// A tap saves the word — or, after a long press on another word in the
    /// same line, the phrase running between the two.
    private func tap(_ index: Int, in line: Line) {
        let tokens = line.text.split(separator: " ").map(String.init)
        defer { phraseStart = nil }
        if let start = phraseStart, start.line == line.id, start.index != index {
            save(Self.clean(tokens[min(start.index, index)...max(start.index, index)].joined(separator: " ")),
                 from: line)
        } else {
            save(Self.clean(tokens[index]), from: line)
        }
    }

    /// Trims the punctuation a transcript leaves on the ends — "Ahnung," — but
    /// keeps what sits inside a phrase.
    private static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
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
            Text(phraseStart == nil ? "Tap a word to keep it.\nHold one to start a phrase." : "Now tap the\nphrase’s last word")
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
