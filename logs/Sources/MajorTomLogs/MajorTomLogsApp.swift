import AppKit
import CallCore
import MajorTomStyle
import SwiftUI

/// Reads the logs the MajorTom apps write to `data/logs/`, live.
@main
struct MajorTomLogsApp: App {
    @State private var model = LogModel()

    var body: some Scene {
        Window("MajorTom Logs", id: "logs") {
            LogsView(model: model)
                .frame(minWidth: 760, minHeight: 420)
                .tint(Palette.accent)
        }
        .defaultSize(width: 1000, height: 620)
    }
}

struct Entry: Identifiable, Hashable {
    let id: Int
    let app: String
    let time: Date?
    let level: String
    let message: String
}

@MainActor
@Observable
final class LogModel {
    private(set) var apps: [String] = []
    private(set) var entries: [Entry] = []
    let directory = Log.directory

    private var stamps: [String: Date] = [:]
    private var timer: Timer?

    init() {
        reload()
        // Re-read only what changed, once a second, so new lines show up
        // while an app is running.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reloadIfChanged() }
        }
    }

    private func files() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return names.filter { $0.pathExtension == "log" && !$0.lastPathComponent.hasSuffix(".1.log") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func reloadIfChanged() {
        var next: [String: Date] = [:]
        for url in files() {
            next[url.lastPathComponent] = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
        }
        guard next != stamps else { return }
        reload()
    }

    func reload() {
        var all: [Entry] = []
        var seen: [String] = []
        var stamps: [String: Date] = [:]
        for url in files() {
            let app = url.deletingPathExtension().lastPathComponent
            seen.append(app)
            stamps[url.lastPathComponent] = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            // The last few thousand lines are plenty to read through.
            for line in text.split(separator: "\n").suffix(5000) {
                let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
                if parts.count == 3 {
                    all.append(Entry(id: 0, app: app, time: Self.parse(String(parts[0])),
                                     level: String(parts[1]), message: String(parts[2])))
                } else {
                    all.append(Entry(id: 0, app: app, time: nil, level: "info", message: String(line)))
                }
            }
        }
        // Stable order: by time, keeping each file's own order for ties.
        let sorted = all.enumerated().sorted {
            ($0.element.time ?? .distantPast, $0.offset) < ($1.element.time ?? .distantPast, $1.offset)
        }
        entries = sorted.enumerated().map { index, pair in
            let e = pair.element
            return Entry(id: index, app: e.app, time: e.time, level: e.level, message: e.message)
        }
        apps = seen
        self.stamps = stamps
    }

    /// Empties one app's log, or all of them.
    func clear(_ app: String?) {
        for url in files() where app == nil || url.deletingPathExtension().lastPathComponent == app {
            try? Data().write(to: url)
        }
        reload()
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func parse(_ s: String) -> Date? { iso.date(from: s) }
}

struct LogsView: View {
    let model: LogModel
    /// Which log to show; `all` interleaves every app's by time.
    @State private var selection = LogsView.all
    private static let all = "\u{0}all"

    private var app: String? { selection == Self.all ? nil : selection }
    @State private var problemsOnly = false
    @State private var search = ""
    @State private var clearing = false

    private var shown: [Entry] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        return model.entries.filter { entry in
            (app == nil || entry.app == app)
                && (!problemsOnly || entry.level != "info")
                && (needle.isEmpty || entry.message.lowercased().contains(needle))
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("All apps", systemImage: "square.stack.3d.up").tag(Self.all)
                Section("Apps") {
                    ForEach(model.apps, id: \.self) { name in
                        Label(name, systemImage: Self.icon(name)).tag(name)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            let shown = shown
            Group {
                if shown.isEmpty {
                    ContentUnavailableView(
                        model.entries.isEmpty ? "No logs yet" : "Nothing matches",
                        systemImage: "text.alignleft",
                        description: Text(model.entries.isEmpty
                            ? "The MajorTom apps write here as they run: \(model.directory.path)"
                            : "Try another app, or clear the search."))
                } else {
                    FollowingScrollView(following: shown.count) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(shown) { EntryRow(entry: $0, showsApp: app == nil) }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .background(Palette.background)
            .navigationTitle(app ?? "All apps")
            .navigationSubtitle("\(shown.count) lines")
            .searchable(text: $search, placement: .toolbar, prompt: "Search")
            .toolbar {
                ToolbarItemGroup {
                    Toggle(isOn: $problemsOnly) {
                        Label("Warnings and errors only", systemImage: "exclamationmark.triangle")
                    }
                    .help("Only warnings and errors")
                    Button { NSWorkspace.shared.open(model.directory) } label: {
                        Label("Open folder", systemImage: "folder")
                    }
                    .help("Show the log files in Finder")
                    Button { clearing = true } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .help(app.map { "Empty the \($0) log" } ?? "Empty every log")
                }
            }
            .confirmationDialog(app.map { "Clear the \($0) log?" } ?? "Clear every log?",
                                isPresented: $clearing) {
                Button("Clear", role: .destructive) { model.clear(app) }
            }
        }
    }

    private static func icon(_ app: String) -> String {
        switch app {
        case "calls": return "waveform"
        case "desktop": return "books.vertical"
        case "browser-sync": return "globe"
        default: return "doc.plaintext"
        }
    }
}

private struct EntryRow: View {
    let entry: Entry
    let showsApp: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(entry.time.map(Self.format) ?? "")
                .foregroundStyle(Palette.tertiary)
                .frame(width: 130, alignment: .leading)
            Text(entry.level.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 44, alignment: .leading)
            if showsApp {
                Text(entry.app)
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 96, alignment: .leading)
                    .lineLimit(1)
            }
            Text(entry.message)
                .foregroundStyle(entry.level == "info" ? Palette.text : color)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12.5, design: .monospaced))
        .textSelection(.enabled)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(entry.level == "error" ? Palette.badSoft.opacity(0.6) : .clear)
    }

    private var color: Color {
        switch entry.level {
        case "error": return Palette.badText
        case "warn": return Palette.warmText
        default: return Palette.secondary
        }
    }

    private static func format(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute().second())
    }
}
