import CallCore
import Foundation

/// Receives words from the phone. The phone pushes — it finds this Mac over
/// Bonjour and sends — so the listener runs for as long as the app is open and
/// there is nothing here to press.
@MainActor
final class PhoneSync: ObservableObject {
    @Published private(set) var listening = false
    @Published private(set) var lastArrival: String?
    @Published private(set) var failure: String?

    private var server: SyncServer?
    private let onArrival: () -> Void

    init(onArrival: @escaping () -> Void) {
        self.onArrival = onArrival
    }

    func clearArrival() {
        lastArrival = nil
    }

    func start() {
        guard server == nil else { return }
        do {
            let server = SyncServer(database: try CallCore.Database()) { [weak self] report in
                Task { @MainActor in
                    self?.lastArrival = "\(report.words) \(report.words == 1 ? "word" : "words") from your phone (\(report.person))"
                    self?.onArrival()
                }
            }
            try server.start()
            self.server = server
            listening = true
        } catch {
            failure = "\(error)"
        }
    }
}
