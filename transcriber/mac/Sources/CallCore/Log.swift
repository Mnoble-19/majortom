#if os(macOS)
import Foundation

/// A plain text log per app in `data/logs/`, read by MajorTom Logs.
///
/// Events and counts only — never what was said, the words saved from a call,
/// or who it was with. Those stay private even from the log.
public enum Log {
    public enum Level: String, Sendable {
        case info, warn, error
    }

    /// Which file to write: "calls", "desktop".
    nonisolated(unsafe) public static var app = "app"

    public static func info(_ message: String) { write(.info, message) }
    public static func warn(_ message: String) { write(.warn, message) }
    public static func error(_ message: String) { write(.error, message) }

    /// The folder beside the library, so it is found the same way.
    public static var directory: URL {
        Database.defaultURL().deletingLastPathComponent().appending(path: "logs", directoryHint: .isDirectory)
    }

    /// One line a message: time, level, text — tab-separated so the viewer can
    /// split it without guessing.
    public static func write(_ level: Level, _ message: String) {
        let flat = message.replacingOccurrences(of: "\n", with: " ")
        let line = "\(ISO8601.string())\t\(level.rawValue)\t\(flat)\n"
        queue.async {
            let fm = FileManager.default
            let dir = directory
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appending(path: "\(app).log")
            rotate(url)
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }

    private static let queue = DispatchQueue(label: "majortom.log")
    private static let maxBytes = 2_000_000

    /// Keeps one previous file, so the log never grows without bound.
    private static func rotate(_ url: URL) {
        let fm = FileManager.default
        guard let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int,
              size > maxBytes else { return }
        let old = url.deletingPathExtension().appendingPathExtension("1.log")
        try? fm.removeItem(at: old)
        try? fm.moveItem(at: url, to: old)
    }
}
#endif
