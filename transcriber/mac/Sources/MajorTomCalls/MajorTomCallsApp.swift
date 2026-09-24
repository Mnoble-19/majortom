import AppKit
import CallCore
import MajorTomStyle
import SwiftUI

@main
struct MajorTomCallsApp: App {
    @State private var model = SessionModel()

    var body: some Scene {
        Window("Calls", id: "calls") {
            CallView(model: model)
                .frame(minWidth: 680, minHeight: 460)
                .tint(Palette.accent)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 900, height: 600)

        // The window has to stay reachable while the call app is in front, and a
        // menu bar item is the one place that is always visible. Starting a
        // session from here means not hunting for the window first.
        MenuBarExtra("Calls", systemImage: model.isRunning ? "waveform.circle.fill" : "waveform.circle") {
            if model.isRunning {
                Text("Listening to \(model.person) · \(model.saved.count) saved")
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
    @AppStorage("floatAboveOthers") private var floatAboveOthers = true

    var body: some View {
        Group {
            if model.isRunning {
                HStack(spacing: 0) {
                    TranscriptView(model: model)
                    SavedWordsView(words: model.saved, onEdit: model.update, onDelete: model.remove)
                        .frame(width: 260)
                }
            } else if let finished = model.finished {
                SummaryView(person: finished.person, words: model.saved,
                            onEdit: model.update, onDelete: model.remove, onNewCall: model.startOver)
            } else {
                SetupView(model: model)
            }
        }
        .background(Palette.background)
        .toolbar { toolbar }
        .onChange(of: floatAboveOthers) { _, float in setFloating(float) }
        .onAppear { setFloating(floatAboveOthers) }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if model.isRunning {
                SessionHeader(model: model)
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: $floatAboveOthers) {
                Label("Keep on top", systemImage: floatAboveOthers ? "pin.fill" : "pin")
            }
            .help("Keep this window above the call app")
            if model.isRunning {
                Button(role: .destructive) { Task { await model.end() } } label: {
                    Text("End").font(.rounded(13, .bold)).padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.bad)
            }
        }
    }

    private func setFloating(_ float: Bool) {
        for window in NSApp.windows where window.canBecomeKey {
            window.level = float ? .floating : .normal
        }
    }
}

/// Who, how long, and what is being heard — the one line worth glancing at
/// mid-call.
private struct SessionHeader: View {
    let model: SessionModel

    var body: some View {
        HStack(spacing: 10) {
            Avatar(name: model.person, size: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text(model.person).font(.rounded(14, .heavy))
                HStack(spacing: 4) {
                    if let started = model.startedAt {
                        TimelineView(.periodic(from: started, by: 1)) { context in
                            Text(Duration.seconds(context.date.timeIntervalSince(started))
                                .formatted(.time(pattern: .minuteSecond)))
                                .monospacedDigit()
                        }
                    }
                    if let app = model.tappedApp {
                        Text("· hearing \(app)")
                    }
                }
                .font(.rounded(11, .medium))
                .foregroundStyle(Palette.secondary)
            }
        }
    }
}

struct Avatar: View {
    let name: String
    var size: CGFloat = 38

    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.rounded(size * 0.45, .heavy))
            .foregroundStyle(Palette.calls.ink)
            .frame(width: size, height: size)
            .background(Palette.calls.fill, in: Circle())
    }
}

/// Before a call: who it is with and how they speak.
private struct SetupView: View {
    let model: SessionModel
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 22) {
            Avatar(name: model.person.isEmpty ? "?" : model.person, size: 72)

            VStack(spacing: 6) {
                Text("Who are you talking to?").font(.rounded(24, .heavy))
                Text("Start the call first. What they say is transcribed live; click any word to keep it with its sentence. The transcript itself is never saved.")
                    .font(.rounded(14))
                    .foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            TextField("Name", text: Binding(get: { model.person }, set: { model.person = $0 }))
                .textFieldStyle(.plain)
                .font(.rounded(22, .bold))
                .multilineTextAlignment(.center)
                .padding(.vertical, 12)
                .frame(width: 300)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .focused($nameFocused)

            Picker("Spoken in", selection: Binding(
                get: { model.localeIdentifier }, set: { model.localeIdentifier = $0 })) {
                Text("Germany").tag("de-DE")
                Text("Austria").tag("de-AT")
                Text("Switzerland").tag("de-CH")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 300)

            Button {
                Task { await model.start() }
            } label: {
                Label("Start listening", systemImage: "waveform")
                    .font(.rounded(16, .bold))
                    .frame(width: 268, height: 44)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .keyboardShortcut(.defaultAction)
            .disabled(model.person.trimmingCharacters(in: .whitespaces).isEmpty)

            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.rounded(13, .medium))
                    .foregroundStyle(Palette.warmText)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { nameFocused = model.person.isEmpty }
    }
}

/// After a call: what was saved, and the way on to translating it. Calls save
/// words without a meaning; the library app fills those in.
private struct SummaryView: View {
    let person: String
    let words: [SavedWord]
    let onEdit: (SavedWord.ID, String, String) -> Void
    let onDelete: (SavedWord.ID) -> Void
    let onNewCall: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                Text("Call with \(person)").font(.rounded(24, .heavy))
                Text("\(words.count) \(words.count == 1 ? "word" : "words") saved. Fix or trim them here, then translate them in MajorTom, under Calls.")
                    .font(.rounded(14))
                    .foregroundStyle(Palette.secondary)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(words) { word in
                        SavedWordRow(word: word, onEdit: onEdit, onDelete: onDelete)
                    }
                }
            }
            .frame(maxWidth: 460, maxHeight: 280)

            HStack(spacing: 12) {
                Button("New call", action: onNewCall)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                Button("Open in MajorTom", action: openLibrary)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openLibrary() {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.majortom.desktop")
        else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }
}
