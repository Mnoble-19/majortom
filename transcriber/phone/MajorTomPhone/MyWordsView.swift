import CallCore
import MajorTomStyle
import SwiftUI

/// Type in a word you want to learn — one you read on a sign, or looked up
/// yourself. It waits with the rest and goes to "My words" on the Mac.
struct MyWordsView: View {
    let pending: PendingWords

    @State private var text = ""
    @State private var sentence = ""
    @FocusState private var focused: Field?

    private enum Field { case text, sentence }

    var body: some View {
        List {
            Section {
                TextField("Word or phrase", text: $text)
                    .font(.rounded(24, .heavy))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .text)
                    .submitLabel(.next)
                    .onSubmit { focused = .sentence }
                TextField("A sentence with it (optional)", text: $sentence, axis: .vertical)
                    .font(.rounded(17))
                    .focused($focused, equals: .sentence)
                Button(action: add) {
                    Label("Add word", systemImage: "plus")
                        .font(.rounded(17, .bold))
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                .listRowSeparator(.hidden)
            } footer: {
                Text("Your Mac translates it when you send, and the sentence helps it pick the right meaning.")
            }
            .listRowBackground(Palette.card)

            if !pending.ownWords.isEmpty {
                Section("Waiting to send") {
                    ForEach(pending.ownWords.reversed(), id: \.text) { word in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(word.text).font(.rounded(19, .heavy))
                            if let translation = word.translation {
                                Text(translation).font(.rounded(15)).foregroundStyle(Palette.accentText)
                            }
                            if !word.sentence.isEmpty {
                                Text(word.sentence).font(.rounded(14)).foregroundStyle(Palette.secondary)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                pending.remove(word.text, from: PendingWords.ownSessionID)
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
                .listRowBackground(Palette.card)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle("My words")
    }

    private func add() {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        pending.addOwn(word, sentence: sentence.trimmingCharacters(in: .whitespacesAndNewlines))
        text = ""
        sentence = ""
        focused = .text
    }
}
