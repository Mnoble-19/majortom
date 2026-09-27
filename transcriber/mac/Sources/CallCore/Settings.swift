import Foundation
import Security

/// How to reach a local (or remote) OpenAI-compatible model.
public struct LLMSettings: Codable, Equatable, Sendable {
    /// Base URL including the version path, e.g. `http://localhost:9931/v1`.
    public var endpoint: String
    public var model: String
    /// Ask the model not to think before answering. Much faster and noticeably
    /// worse — a reasoning model given `abbringen` in context answers "to be
    /// dissuaded" with thinking on and a generic "to divert, to dissuade, to
    /// distract" with it off. Off by default, because the translation arrives
    /// in the background and nobody is waiting on it.
    public var skipReasoning: Bool
    public var enabled: Bool
    /// Most tokens one reply may use, thinking included. A thinking model
    /// needs room: Gemma 4 26B used up to ~1,500 on one phrase, and at 900 it
    /// was cut off before answering.
    public var maxTokens: Int = 8192
    /// How long to wait for one reply. A cold server loads the model first,
    /// and thinking at ~20 tokens a second can run to minutes.
    public var timeout: Double = 600

    public init(endpoint: String, model: String, skipReasoning: Bool, enabled: Bool) {
        self.endpoint = endpoint
        self.model = model
        self.skipReasoning = skipReasoning
        self.enabled = enabled
    }

    /// Tolerates settings saved before a field existed, so adding one never
    /// throws away the rest.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            endpoint: try c.decodeIfPresent(String.self, forKey: .endpoint) ?? Self.empty.endpoint,
            model: try c.decodeIfPresent(String.self, forKey: .model) ?? "",
            skipReasoning: try c.decodeIfPresent(Bool.self, forKey: .skipReasoning) ?? false,
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true)
        maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens) ?? maxTokens
        timeout = try c.decodeIfPresent(Double.self, forKey: .timeout) ?? timeout
    }

    public static let empty = LLMSettings(
        endpoint: "http://localhost:9931/v1",
        model: "",
        skipReasoning: false,
        enabled: true
    )
}

public enum Settings {
    private static let defaults = UserDefaults.standard
    private static let llmKey = "llm.settings"

    public static var llm: LLMSettings {
        get {
            guard let data = defaults.data(forKey: llmKey),
                  let decoded = try? JSONDecoder().decode(LLMSettings.self, from: data) else {
                return .empty
            }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: llmKey)
        }
    }

    /// The person you spoke to last, so the next session starts pre-filled.
    public static var lastPerson: String {
        get { defaults.string(forKey: "lastPerson") ?? "" }
        set { defaults.set(newValue, forKey: "lastPerson") }
    }

    /// Per-person recognizer locale. Austrian and Swiss German are different
    /// enough to be worth picking, and the models for both are already
    /// installed, so the right variant is free accuracy.
    public static func locale(forPerson person: String) -> String {
        defaults.string(forKey: "locale.\(person.lowercased())") ?? "de-DE"
    }

    public static func setLocale(_ identifier: String, forPerson person: String) {
        defaults.set(identifier, forKey: "locale.\(person.lowercased())")
    }

    /// The API key lives in the keychain rather than in `UserDefaults` beside
    /// everything else: a local llama.cpp needs no key, but pointing this at a
    /// hosted endpoint would otherwise leave a real credential in a plist that
    /// any process running as you can read.
    public static var apiKey: String {
        get { Keychain.read() ?? "" }
        set { Keychain.write(newValue) }
    }
}

private enum Keychain {
    private static let service = "com.majortom.transcriber"
    private static let account = "llm-api-key"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String) {
        SecItemDelete(baseQuery as CFDictionary)
        guard !value.isEmpty else { return }
        var query = baseQuery
        query[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(query as CFDictionary, nil)
    }
}
