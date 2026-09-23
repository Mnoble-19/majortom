import AppKit
import CallCore
import SwiftUI

@main
struct MajorTomCallsApp: App {
    @State private var model = SessionModel()

    var body: some Scene {
        Window("Calls", id: "calls") {
            CallView(model: model)
                .frame(minWidth: 620, minHeight: 420)
        }
        .defaultSize(width: 760, height: 540)

        Settings { SettingsView() }

        // The window has to stay reachable while the call app is in front, and a
        // menu bar item is the one place that is always visible. Starting a
        // session from here means not hunting for the window first.
        MenuBarExtra("Calls", systemImage: model.isRunning ? "waveform.circle.fill" : "waveform.circle") {
            if model.isRunning {
                Text("Recording \(model.person)")
                Button("End session") { Task { await model.end() } }
            } else {
                Button("Start session with \(model.person.isEmpty ? "…" : model.person)") {
                    Task { await model.start() }
                }
                .disabled(model.person.isEmpty)
            }
            Divider()
            Button("Show window") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first { $0.canBecomeKey }?.makeKeyAndOrderFront(nil)
            }
            Button("Quit") { NSApp.terminate(nil) }
        }
    }
}

struct CallView: View {
    let model: SessionModel
    @Environment(\.openSettings) private var openSettings
    @State private var floatAboveOthers = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                transcript.frame(minWidth: 320)
                SavedWordsView(words: model.saved, onCorrect: model.recorrect)
                    .frame(minWidth: 230)
            }
        }
        .task { await model.refreshTranslationAvailability() }
        .onChange(of: floatAboveOthers) { _, float in setFloating(float) }
        .onAppear { setFloating(floatAboveOthers) }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if model.isRunning {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text(model.person).font(.headline)
                if let app = model.tappedApp {
                    Text("· hearing \(app)").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("· mic only, no app playing audio")
                        .font(.caption).foregroundStyle(.orange)
                }
                Spacer()
                Button("End") { Task { await model.end() } }
            } else {
                TextField("Who are you talking to?", text: Binding(
                    get: { model.person }, set: { model.person = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 190)
                    .onSubmit { Task { await model.start() } }

                Picker("", selection: Binding(
                    get: { model.localeIdentifier }, set: { model.localeIdentifier = $0 })) {
                    Text("Germany").tag("de-DE")
                    Text("Austria").tag("de-AT")
                    Text("Switzerland").tag("de-CH")
                }
                .labelsHidden()
                .frame(width: 130)

                Button("Start") { Task { await model.start() } }
                    .keyboardShortcut(.return)
                    .disabled(model.person.isEmpty)
                Spacer()
            }

            Toggle("Float", isOn: $floatAboveOthers)
                .toggleStyle(.checkbox)
                .help("Keep this window above the call app")
            Button { openSettings() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
        }
        .padding(10)
    }

    private var transcript: some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange).font(.callout).padding(.bottom, 8)
                    }

                    if !model.isRunning && model.lines.isEmpty {
                        idleHint
                    }

                    ForEach(model.lines) { line in
                        LineView(
                            line: line,
                            person: model.person,
                            savedWords: savedWordSet,
                            onTap: { model.save(word: $0, from: line) })
                        .id(line.id)
                    }

                    // What the recognizer has heard but not committed. Not
                    // clickable: it is still being revised, so a word here can
                    // change under the click.
                    ForEach(Speaker.allCasesInOrder, id: \.self) { speaker in
                        if let text = model.volatile[speaker], !text.isEmpty {
                            Text(text)
                                .font(.system(size: 15))
                                .foregroundStyle(.tertiary)
                                .italic()
                                .padding(.vertical, 5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(12)
            }
            .onChange(of: model.lines.count) { _, _ in
                withAnimation { scroll.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private var idleHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Name the person and press Start.")
                .foregroundStyle(.secondary)
            Text("It transcribes both sides — their voice from whichever app is playing audio, yours from the mic. Click a word to save it with its sentence. The transcript is not kept; only saved words are.")
                .font(.caption).foregroundStyle(.tertiary)
            if !model.appleTranslationReady {
                Text("Apple's German translation is not installed, so saved words wait for the local model rather than showing a rough answer first. Settings explains where to turn it on.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.bottom, 10)
    }

    private var savedWordSet: Set<String> {
        Set(model.saved.map { $0.word.lowercased() })
    }

    private func setFloating(_ float: Bool) {
        for window in NSApp.windows where window.canBecomeKey {
            window.level = float ? .floating : .normal
        }
    }
}

extension Speaker {
    /// Their line above yours, so the volatile tail reads in the order you would
    /// expect rather than whatever the dictionary hands back.
    static var allCasesInOrder: [Speaker] { [.them, .me] }
}
