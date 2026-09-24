import CallCore
import Foundation
import Network
import Observation

/// Finds the Mac and sends it what is waiting.
///
/// Bonjour does the finding, so there is no address to type. It works over
/// peer-to-peer Wi-Fi as well as a shared network, and because it is not an
/// internet route a VPN on either device stays out of the way.
@MainActor
@Observable
final class SyncModel {
    private(set) var macs: [Found] = []
    private(set) var state: State = .idle
    private(set) var lastResult: String?

    struct Found: Identifiable, Equatable {
        let id: String
        let endpoint: NWEndpoint
        var name: String { id }
    }

    enum State: Equatable {
        case idle
        case looking
        case sending
        case done(Int)
        case failed(String)
    }

    private var browser: NWBrowser?

    func startLooking() {
        guard browser == nil else { return }
        state = .looking
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjour(type: SyncProtocol.serviceType, domain: nil),
            using: parameters)

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.macs = results.compactMap { result in
                    guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                    return Found(id: name, endpoint: result.endpoint)
                }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stopLooking() {
        browser?.cancel()
        browser = nil
        if state == .looking { state = .idle }
    }

    /// Sends every waiting session, clearing each only once the Mac has
    /// confirmed it — so a sync that dies halfway keeps the rest.
    func send(_ pending: PendingWords, to mac: Found) async {
        state = .sending
        lastResult = nil
        let client = SyncClient()
        var sent = 0

        for payload in pending.payloads() {
            do {
                let result = try await client.send(payload, to: mac.endpoint)
                if let error = result.error {
                    state = .failed(error)
                    return
                }
                sent += result.accepted
                pending.removeSession(payload.sessionID)
            } catch {
                state = .failed("\(error)")
                return
            }
        }
        state = .done(sent)
        lastResult = sent == 0 ? "Nothing waiting" : "Sent \(sent) word\(sent == 1 ? "" : "s")"
    }
}
