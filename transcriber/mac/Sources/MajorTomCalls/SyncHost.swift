import CallCore
import Foundation
import Observation

/// The Mac's side of phone sync, running for as long as the app is open.
///
/// It is not tied to a session: words arrive from the phone whenever the two
/// devices are near each other, which is rarely the moment you happen to be on
/// a call.
@MainActor
@Observable
final class SyncHost {
    private(set) var isListening = false
    private(set) var port: UInt16?
    private(set) var failure: String?
    /// Most recent arrivals, newest first, so a sync visibly lands.
    private(set) var arrivals: [Arrival] = []

    struct Arrival: Identifiable {
        let id = UUID()
        let person: String
        let words: Int
        let at = Date()
        var translated: Int?
    }

    private var server: SyncServer?
    private var database: Database?

    func start() {
        guard server == nil else { return }
        do {
            let database = try Database()
            self.database = database
            let server = SyncServer(
                database: database,
                // Read per import, so changing the endpoint in Settings takes
                // effect without restarting anything.
                translator: { Translator() }
            ) { [weak self] report in
                Task { @MainActor in
                    self?.record(report)
                }
            }
            try server.start()
            self.server = server
            isListening = true
            // The port is assigned asynchronously once the listener is ready.
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                port = server.port
            }
        } catch {
            failure = "\(error)"
            isListening = false
        }
    }

    func stop() {
        server?.stop()
        server = nil
        isListening = false
        port = nil
    }

    private func record(_ report: SyncServer.Report) {
        arrivals.insert(
            Arrival(person: report.person, words: report.words), at: 0)
        if arrivals.count > 5 { arrivals.removeLast() }

        // The server translates in the background after acknowledging; watch
        // the row empty out so the count on screen means something.
        let sourceID = report.sourceID
        let id = arrivals[0].id
        Task { [weak self] in
            guard let database = self?.database else { return }
            for _ in 0..<120 {
                try? await Task.sleep(for: .seconds(2))
                let pending = (try? database.untranslatedItems(sourceID: sourceID))?.count ?? 0
                guard let self else { return }
                if let index = self.arrivals.firstIndex(where: { $0.id == id }) {
                    self.arrivals[index].translated = report.words - pending
                }
                if pending == 0 { return }
            }
        }
    }
}
