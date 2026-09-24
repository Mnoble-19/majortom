import CallCore
import Foundation
import SwiftUI

/// Receives words from the phone, and fills in translations for anything in the
/// library that still has none.
///
/// Both jobs live here rather than in the calls app because they are library
/// concerns, not call concerns. The backlog in particular covers every source:
/// a word saved on the reMarkable with no wifi, or in the browser while DeepL
/// was down, is the same problem as one synced from the phone.
///
/// Listening runs for as long as this app is open. The phone pushes — it finds
/// the Mac over Bonjour and sends — so there is nothing here to press for that
/// half; the button is for the translating.
@MainActor
final class PhoneSync: ObservableObject {
    enum Outcome: Equatable {
        case translated(Int)
        case nothingWaiting
        case noModel
        case failed(String)

        var message: String {
            switch self {
            case let .translated(n): return "Translated \(n) \(n == 1 ? "word" : "words")"
            case .nothingWaiting: return "Everything is translated"
            case .noModel: return "No model configured — see Settings"
            case let .failed(why): return why
            }
        }

        /// A missing model is worth flagging; the rest are ordinary outcomes.
        var isFailure: Bool {
            switch self {
            case .failed, .noModel: return true
            default: return false
            }
        }
    }

    @Published private(set) var listening = false
    @Published private(set) var translating = false
    @Published private(set) var waiting = 0
    @Published private(set) var lastArrival: String?
    @Published private(set) var outcome: Outcome?

    private var server: SyncServer?
    private var database: CallCore.Database?
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard server == nil else { return }
        do {
            let database = try CallCore.Database()
            self.database = database
            let server = SyncServer(database: database) { [weak self] report in
                Task { @MainActor in
                    self?.lastArrival = "\(report.person): \(report.words) from your phone"
                    self?.onChange()
                    self?.refreshWaiting()
                    // Translate what just landed without being asked. The
                    // button exists for the backlog, not for the common case.
                    self?.translateWaiting()
                }
            }
            try server.start()
            self.server = server
            listening = true
            refreshWaiting()
        } catch {
            outcome = .failed("\(error)")
        }
    }

    func refreshWaiting() {
        waiting = (try? database?.untranslatedItems().count) ?? 0
    }

    /// Fills in every item in the library that has no translation yet.
    func translateWaiting() {
        guard !translating else { return }
        guard let database else { return }

        let settings = Settings.llm
        let pending = (try? database.untranslatedItems()) ?? []
        guard !pending.isEmpty else {
            outcome = .nothingWaiting
            return
        }
        guard settings.enabled, !settings.model.isEmpty else {
            outcome = .noModel
            return
        }

        translating = true
        outcome = nil

        Task {
            let translator = Translator(settings: settings, apiKey: Settings.apiKey)
            var done = 0
            for item in pending {
                var best: Gloss?
                for await gloss in translator.glosses(word: item.text, sentence: item.context) {
                    best = gloss
                }
                guard let best else { continue }
                try? database.setTranslation(
                    itemID: item.id,
                    translation: best.meaning,
                    contextTranslation: best.sentence)
                done += 1
                refreshWaiting()
                onChange()
            }
            translating = false
            outcome = done == 0
                ? .failed("The model could not be reached")
                : .translated(done)
        }
    }

    func dismiss() {
        outcome = nil
    }
}
