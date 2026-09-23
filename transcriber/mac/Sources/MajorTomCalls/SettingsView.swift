import CallCore
import SwiftUI

/// Endpoint, key, model, and a Test button that actually translates something
/// rather than just checking the port is open.
struct SettingsView: View {
    @State private var settings = Settings.llm
    @State private var apiKey = Settings.apiKey
    @State private var models: [String] = []
    @State private var result: Result?
    @State private var busy = false
    @State private var appleReady: Bool?

    private enum Result {
        case ok(Gloss, TimeInterval)
        case bad(String)
    }

    var body: some View {
        Form {
            Section("Local model") {
                TextField("Endpoint", text: $settings.endpoint,
                          prompt: Text("http://localhost:9931/v1"))
                    .textContentType(.URL)

                SecureField("API key", text: $apiKey,
                            prompt: Text("leave empty for a local model"))

                HStack {
                    if models.isEmpty {
                        TextField("Model", text: $settings.model,
                                  prompt: Text("press Fetch to list what is loaded"))
                    } else {
                        Picker("Model", selection: $settings.model) {
                            ForEach(models, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Button("Fetch") { Task { await fetchModels() } }
                        .disabled(settings.endpoint.isEmpty || busy)
                }

                Toggle("Answer faster, think less", isOn: $settings.skipReasoning)
                Text(settings.skipReasoning
                     ? "About 2s. Glosses come back in whatever form the word was in — \"dropped off\" rather than \"to post\"."
                     : "About 7–15s, in the background. Gives proper dictionary forms, which is what you want in the library.")
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("Use the model at all", isOn: $settings.enabled)
            }

            Section {
                HStack {
                    Button("Test") { Task { await test() } }
                        .disabled(settings.model.isEmpty || busy)
                    if busy { ProgressView().controlSize(.small) }
                    Spacer()
                }

                switch result {
                case .ok(let gloss, let seconds):
                    VStack(alignment: .leading, spacing: 3) {
                        Label(String(format: "Working — answered in %.1fs", seconds),
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).font(.callout)
                        Text("abbringen → \(gloss.meaning)").font(.caption)
                        Text(gloss.sentence).font(.caption).foregroundStyle(.secondary)
                    }
                case .bad(let message):
                    Label(message, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red).font(.callout)
                        .textSelection(.enabled)
                case nil:
                    Text("Translates a real sentence, so a wrong model name shows up here rather than mid-call.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Apple translation") {
                switch appleReady {
                case true:
                    Label("German → English installed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.callout)
                    Text("Used for an instant first answer while the model thinks.")
                        .font(.caption).foregroundStyle(.secondary)
                case false:
                    Label("German → English not installed", systemImage: "arrow.down.circle")
                        .font(.callout)
                    Text("Optional. Without it, saved words wait for the model instead of showing a rough translation immediately.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Open Language & Region") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                case nil:
                    ProgressView().controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onChange(of: settings) { _, new in Settings.llm = new }
        .onChange(of: apiKey) { _, new in Settings.apiKey = new }
        .task { appleReady = await AppleTranslator().isAvailable() }
    }

    private func fetchModels() async {
        busy = true
        defer { busy = false }
        do {
            models = try await ModelTranslator(settings: settings, apiKey: apiKey).models()
            if settings.model.isEmpty { settings.model = models.first ?? "" }
            if !models.contains(settings.model) { settings.model = models.first ?? "" }
        } catch {
            result = .bad("\(error)")
        }
    }

    private func test() async {
        busy = true
        result = nil
        defer { busy = false }
        let started = Date()
        do {
            let gloss = try await ModelTranslator(settings: settings, apiKey: apiKey).test()
            result = .ok(gloss, -started.timeIntervalSinceNow)
        } catch {
            result = .bad("\(error)")
        }
    }
}
