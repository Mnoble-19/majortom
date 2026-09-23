import Foundation
import Network

/// What the phone sends. One in-person session and the words picked during it,
/// each with the sentence it came from and no translation — the phone has no
/// model, so the Mac fills those in on arrival.
public struct SyncPayload: Codable, Sendable {
    public var sessionID: String
    public var person: String
    public var startedAt: Date
    public var words: [Word]

    public struct Word: Codable, Sendable {
        public var text: String
        public var sentence: String
        public var position: TimeInterval

        public init(text: String, sentence: String, position: TimeInterval) {
            self.text = text
            self.sentence = sentence
            self.position = position
        }
    }

    public init(sessionID: String, person: String, startedAt: Date, words: [Word]) {
        self.sessionID = sessionID
        self.person = person
        self.startedAt = startedAt
        self.words = words
    }
}

public struct SyncResult: Codable, Sendable {
    public var accepted: Int
    /// Present when something went wrong, so the phone can show it rather than
    /// silently reporting success.
    public var error: String?

    public init(accepted: Int, error: String? = nil) {
        self.accepted = accepted
        self.error = error
    }
}

public enum SyncProtocol {
    /// Bonjour type. The phone browses for this instead of asking anyone to
    /// type an IP address.
    public static let serviceType = "_majortom._tcp"
    public static let defaultPort: UInt16 = 51_847

    /// A four-byte big-endian length then that many bytes of JSON — the same
    /// framing the browser extension's native host already uses, rather than a
    /// second convention to remember.
    public static func frame(_ data: Data) -> Data {
        var length = UInt32(data.count).bigEndian
        var out = Data(bytes: &length, count: 4)
        out.append(data)
        return out
    }

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

#if os(macOS)
/// Writes a synced session into the library. Words arrive untranslated and are
/// filled in afterwards, one at a time, so a slow model does not hold the phone
/// waiting on a reply.
public struct SyncImporter: Sendable {
    private let database: Database

    public init(database: Database) {
        self.database = database
    }

    public func importSession(_ payload: SyncPayload) throws -> Int64 {
        let title = Session.title(person: payload.person, at: payload.startedAt)
        let sourceID = try database.upsertSource(
            title: title,
            person: payload.person,
            sessionID: payload.sessionID,
            origin: "phone",
            createdAt: payload.startedAt)

        for word in payload.words {
            try database.upsertItem(
                sourceID: sourceID,
                text: word.text,
                translation: "",
                context: word.sentence,
                position: word.position,
                createdAt: payload.startedAt)
        }
        return sourceID
    }

    /// Translates everything in a source that still has none. Runs after the
    /// import has already been acknowledged.
    @discardableResult
    public func fillTranslations(sourceID: Int64, translator: Translator = Translator()) async -> Int {
        guard let pending = try? database.untranslatedItems(sourceID: sourceID) else { return 0 }
        var filled = 0
        for item in pending {
            var best: Gloss?
            for await gloss in translator.glosses(word: item.text, sentence: item.context) {
                best = gloss
            }
            guard let best else { continue }
            try? database.setTranslation(
                itemID: item.id, translation: best.meaning, contextTranslation: best.sentence)
            filled += 1
        }
        return filled
    }
}

/// Listens on the local network for the phone. Advertised over Bonjour so the
/// phone finds it without anyone typing an address, which is the whole point —
/// and it is a peer-to-peer link rather than an internet one, so a VPN on
/// either device is not in the path.
public final class SyncServer: @unchecked Sendable {
    public struct Report: Sendable {
        public let person: String
        public let words: Int
        public let sourceID: Int64
    }

    private let importer: SyncImporter
    private var listener: NWListener?
    private let onImport: @Sendable (Report) -> Void
    /// Resolved per import rather than held, so changing the endpoint in
    /// Settings takes effect without restarting the listener.
    private let makeTranslator: @Sendable () -> Translator

    public private(set) var port: UInt16?

    public init(
        database: Database,
        translator: @escaping @Sendable () -> Translator = { Translator() },
        onImport: @escaping @Sendable (Report) -> Void
    ) {
        self.importer = SyncImporter(database: database)
        self.makeTranslator = translator
        self.onImport = onImport
    }

    public func start(port requested: UInt16 = SyncProtocol.defaultPort) throws {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        let listener = try NWListener(
            using: parameters,
            on: NWEndpoint.Port(rawValue: requested) ?? .any)
        listener.service = NWListener.Service(type: SyncProtocol.serviceType)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { [weak self] (state: NWListener.State) in
            if case .ready = state { self?.port = listener.port?.rawValue }
        }
        listener.start(queue: .global(qos: .utility))
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        port = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        readLength(connection)
    }

    private func readLength(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let self, let data, data.count == 4, error == nil else {
                connection.cancel()
                return
            }
            let length = Int(data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
            // A phone sends a few dozen words; anything enormous is a bug or
            // something that is not our client.
            guard length > 0, length < 8_000_000 else {
                connection.cancel()
                return
            }
            self.readBody(connection, length: length)
        }
    }

    private func readBody(_ connection: NWConnection, length: Int) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, _, _ in
            guard let self, let data, data.count == length else {
                connection.cancel()
                return
            }
            self.handle(data, on: connection)
        }
    }

    private func handle(_ data: Data, on connection: NWConnection) {
        let result: SyncResult
        var imported: Report?
        do {
            let payload = try SyncProtocol.decoder.decode(SyncPayload.self, from: data)
            let sourceID = try importer.importSession(payload)
            result = SyncResult(accepted: payload.words.count)
            imported = Report(person: payload.person, words: payload.words.count, sourceID: sourceID)
        } catch {
            result = SyncResult(accepted: 0, error: "\(error)")
        }

        let reply = (try? SyncProtocol.encoder.encode(result)) ?? Data()
        connection.send(content: SyncProtocol.frame(reply), completion: .contentProcessed { _ in
            connection.cancel()
        })

        // Acknowledge first, translate after: the phone should not sit waiting
        // on a model that takes ten seconds a word.
        if let imported {
            onImport(imported)
            Task.detached { [importer, makeTranslator] in
                await importer.fillTranslations(
                    sourceID: imported.sourceID, translator: makeTranslator())
            }
        }
    }
}
#endif

/// The phone's end of the same conversation. Lives here rather than in the iOS
/// app so both sides of the protocol stay in one file.
public struct SyncClient: Sendable {
    public init() {}

    /// Sends one session and waits for the acknowledgement.
    public func send(_ payload: SyncPayload, to host: String, port: UInt16) async throws -> SyncResult {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? .any)
        return try await exchange(payload, endpoint: endpoint, parameters: parameters)
    }

    /// Sends to a Bonjour-discovered Mac, so no address is typed anywhere.
    public func send(_ payload: SyncPayload, to endpoint: NWEndpoint) async throws -> SyncResult {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        return try await exchange(payload, endpoint: endpoint, parameters: parameters)
    }

    private func exchange(
        _ payload: SyncPayload,
        endpoint: NWEndpoint,
        parameters: NWParameters
    ) async throws -> SyncResult {
        let connection = NWConnection(to: endpoint, using: parameters)
        let body = SyncProtocol.frame(try SyncProtocol.encoder.encode(payload))

        return try await withCheckedThrowingContinuation { continuation in
            let resumed = Resumed()

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: body, completion: .contentProcessed { error in
                        if let error {
                            if resumed.claim() { continuation.resume(throwing: error) }
                            connection.cancel()
                            return
                        }
                        Self.readReply(connection) { result in
                            if resumed.claim() { continuation.resume(with: result) }
                            connection.cancel()
                        }
                    })
                case .failed(let error), .waiting(let error):
                    if resumed.claim() { continuation.resume(throwing: error) }
                    connection.cancel()
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    private static func readReply(
        _ connection: NWConnection,
        completion: @escaping (Result<SyncResult, Error>) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { data, _, _, error in
            guard let data, data.count == 4, error == nil else {
                completion(.failure(error ?? SyncError.truncated))
                return
            }
            let length = Int(data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
            connection.receive(minimumIncompleteLength: length, maximumLength: length) { body, _, _, error in
                guard let body, body.count == length, error == nil else {
                    completion(.failure(error ?? SyncError.truncated))
                    return
                }
                completion(Result { try SyncProtocol.decoder.decode(SyncResult.self, from: body) })
            }
        }
    }
}

public enum SyncError: Error, CustomStringConvertible {
    case truncated

    public var description: String { "the reply was cut short" }
}

/// A network callback can fire more than once; a continuation may only be
/// resumed once.
private final class Resumed: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.withLock {
            guard !done else { return false }
            done = true
            return true
        }
    }
}
