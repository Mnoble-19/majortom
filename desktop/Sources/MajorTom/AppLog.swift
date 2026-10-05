import CallCore

/// The shared log, without every file importing CallCore — whose `Database`
/// would clash with this app's own.
///
/// Events and counts only: no words, sentences or names from the library.
enum AppLog {
    static func start(as app: String) { Log.app = app }
    static func info(_ message: String) { Log.info(message) }
    static func warn(_ message: String) { Log.warn(message) }
    static func error(_ message: String) { Log.error(message) }
}
