import CallCore
import SwiftUI

@main
struct MajorTomPhoneApp: App {
    @State private var pending = PendingWords()

    var body: some Scene {
        WindowGroup {
            ContentView(pending: pending)
        }
    }
}

struct ContentView: View {
    let pending: PendingWords
    @State private var session = PhoneSession()
    @State private var sync = SyncModel()

    var body: some View {
        TabView {
            Tab("Talk", systemImage: "waveform") {
                NavigationStack { TalkView(session: session, pending: pending) }
            }
            Tab("Waiting", systemImage: "tray.full") {
                NavigationStack { PendingView(pending: pending, sync: sync) }
                    .badge(pending.totalWords)
            }
        }
    }
}

/// The live screen: transcript scrolling, tap a word to keep it.
struct TalkView: View {
    let session: PhoneSession
    let pending: PendingWords

    var body: some View {
        VStack(spacing: 0) {
            if session.isRunning {
                transcript
            } else {
                setup
            }
            controls
        }
        .navigationTitle(session.isRunning ? session.person : "New conversation")
        .navigationBarTitleDisplayMode(.inline)
        .task { await session.prepareModel() }
    }

    private var setup: some View {
        Form {
            Section {
                TextField("Who are you talking to?", text: Binding(
                    get: { session.person }, set: { session.person = $0 }))
                    .textInputAutocapitalization(.words)

                Picker("German", selection: Binding(
                    get: { session.localeIdentifier }, set: { session.localeIdentifier = $0 })) {
                    Text("Germany").tag("de-DE")
                    Text("Austria").tag("de-AT")
                    Text("Switzerland").tag("de-CH")
                }
            } footer: {
                Text("Tap words as they come up. They are saved with the sentence around them and translated when you sync to your Mac. The recording is not kept.")
            }

            Section {
                switch session.modelState {
                case .downloading:
                    HStack { ProgressView(); Text("Getting the German model…") }
                case .ready:
                    Label("German model ready", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if let engine = session.engine {
                        Text(engine == .speechTranscriber
                             ? "Using the newer recogniser."
                             : "Using system dictation — this device does not support the newer recogniser.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                case .unsupported(let why):
                    Label(why, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange).font(.callout)
                case .unknown:
                    EmptyView()
                }

                if let error = session.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var transcript: some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(session.lines) { line in
                        TappableLine(line: line, saved: savedWords) { word in
                            pending.add(
                                .init(text: word,
                                      sentence: line.sentence(containing: word),
                                      position: line.start),
                                to: session.sessionID,
                                person: session.person,
                                startedAt: session.startedAt)
                        }
                        .id(line.id)
                    }
                    if !session.volatile.isEmpty {
                        Text(session.volatile)
                            .foregroundStyle(.tertiary)
                            .italic()
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding()
            }
            .onChange(of: session.lines.count) { _, _ in
                withAnimation { scroll.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private var savedWords: Set<String> {
        let words = pending.sessions
            .first { $0.id == session.sessionID }?
            .words.map { $0.text.lowercased() } ?? []
        return Set(words)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Divider()
            if session.isRunning {
                Button(role: .destructive) {
                    Task { await session.stop() }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button {
                    Task { await session.start() }
                } label: {
                    Label("Start listening", systemImage: "waveform")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.person.isEmpty || session.modelState != .ready)
            }
        }
        .padding()
    }
}

/// One line with every word tappable. Uses a wrapping `Text` concatenation
/// rather than a custom layout: on a phone the words are large enough that
/// per-word hit targets from a flow layout would be fiddlier than this.
private struct TappableLine: View {
    let line: Line
    let saved: Set<String>
    let onTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(timestamp)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.quaternary)
            FlowWords(words: line.text.split(separator: " ").map(String.init),
                      saved: saved, onTap: onTap)
        }
    }

    private var timestamp: String {
        let total = Int(line.start)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct FlowWords: View {
    let words: [String]
    let saved: Set<String>
    let onTap: (String) -> Void

    var body: some View {
        WrappingStack {
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                let bare = word.trimmingCharacters(in: .punctuationCharacters).lowercased()
                Text(word)
                    .font(.title3)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(saved.contains(bare) ? Color.accentColor.opacity(0.25) : .clear))
                    .onTapGesture { onTap(word) }
            }
        }
    }
}

/// Minimal wrapping layout; SwiftUI still has no built-in one.
struct WrappingStack: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0; y += rowHeight + lineSpacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX; y += rowHeight + lineSpacing; rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// What is waiting to go to the Mac, and the one button that sends it.
struct PendingView: View {
    let pending: PendingWords
    let sync: SyncModel

    var body: some View {
        List {
            if pending.sessions.isEmpty {
                ContentUnavailableView(
                    "Nothing waiting", systemImage: "tray",
                    description: Text("Words you tap during a conversation collect here until you sync."))
            }

            ForEach(pending.sessions) { session in
                Section(session.person) {
                    ForEach(session.words, id: \.text) { word in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(word.text).font(.body.weight(.medium))
                            Text(word.sentence).font(.caption).foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                pending.remove(word.text, from: session.id)
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
            }

            Section("Your Mac") {
                if sync.macs.isEmpty {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Looking…").foregroundStyle(.secondary)
                    }
                }
                ForEach(sync.macs) { mac in
                    Button {
                        Task { await sync.send(pending, to: mac) }
                    } label: {
                        HStack {
                            Label(mac.name, systemImage: "desktopcomputer")
                            Spacer()
                            if sync.state == .sending { ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(sync.state == .sending || pending.totalWords == 0)
                }

                switch sync.state {
                case .done(let count):
                    Label("Sent \(count) word\(count == 1 ? "" : "s")",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failed(let why):
                    Label(why, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange).font(.callout)
                default:
                    EmptyView()
                }
            }
        }
        .navigationTitle("Waiting")
        .onAppear { sync.startLooking() }
        .onDisappear { sync.stopLooking() }
    }
}
