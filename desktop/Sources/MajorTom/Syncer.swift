import Foundation
import SwiftUI

/// Runs `remarkable/sync.py` on demand and reports what it did.
///
/// The script is the one source of truth for how a tablet is read — it is also
/// the command-line path — so the app drives it rather than reimplementing the
/// same import in Swift and letting the two drift.
@MainActor
final class Syncer: ObservableObject {
    enum Outcome: Equatable {
        case imported(Int)
        case nothingNew
        case notConnected
        case failed(String)

        var message: String {
            switch self {
            case let .imported(n): return "Imported \(n) \(n == 1 ? "item" : "items")"
            case .nothingNew: return "Nothing new"
            case .notConnected: return "Tablet not connected"
            case let .failed(why): return why
            }
        }

        /// Only a real failure is worth alarming about. An absent tablet is the
        /// normal state — you sync *because* you just plugged it in.
        var isFailure: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    @Published private(set) var running = false
    @Published private(set) var outcome: Outcome?

    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func sync() {
        guard !running else { return }
        guard let script = AppPaths.repoRoot?
            .appendingPathComponent("remarkable/sync.py"),
            FileManager.default.fileExists(atPath: script.path)
        else {
            outcome = .failed("Cannot find remarkable/sync.py")
            return
        }

        running = true
        outcome = nil

        Task {
            let result = await Self.run(script: script)
            self.outcome = result
            self.running = false
            if case .imported = result { self.onFinish() }
        }
    }

    func dismiss() {
        outcome = nil
    }

    // Both of these run off the main actor: the process blocks, and nothing
    // they touch is UI state.
    private nonisolated static func run(script: URL) async -> Outcome {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                // The system python, not whatever is on the user's PATH: a GUI
                // app does not inherit a shell environment, and /usr/bin/python3
                // is the only interpreter guaranteed to be there.
                process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
                process.arguments = [script.path, "--json"]

                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                do {
                    try process.run()
                } catch {
                    return continuation.resume(returning: .failed("Could not run sync.py"))
                }

                let out = stdout.fileHandleForReading.readDataToEndOfFile()
                let err = stderr.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                continuation.resume(returning: parse(out, fallback: err))
            }
        }
    }

    private nonisolated static func parse(_ stdout: Data, fallback stderr: Data) -> Outcome {
        guard
            let json = try? JSONSerialization.jsonObject(with: stdout) as? [String: Any],
            let status = json["status"] as? String
        else {
            let text = String(data: stderr, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .failed(text?.isEmpty == false ? text! : "sync.py returned nothing readable")
        }

        switch status {
        case "imported": return .imported(json["imported"] as? Int ?? 0)
        case "empty": return .nothingNew
        case "unplugged": return .notConnected
        default: return .failed(json["message"] as? String ?? "Sync failed")
        }
    }
}
