import CallCore
import SwiftUI

/// Conversations you have saved words from, grouped by person.
///
/// Calls skip the platform level shows have, the same way books do. Whether a
/// call was on Signal or in a café is not how you would look for it; who you
/// were talking to is.
struct CallsView: View {
    @EnvironmentObject private var store: Store
    let onOpenCall: (Source) -> Void

    @StateObject private var sync: PhoneSync
    @State private var dismissTask: Task<Void, Never>?

    init(onOpenCall: @escaping (Source) -> Void, store: Store) {
        self.onOpenCall = onOpenCall
        _sync = StateObject(wrappedValue: PhoneSync { store.reload() })
    }

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 24)]

    var body: some View {
        let calls = store.sources(of: .call)

        Group {
            if calls.isEmpty {
                EmptyState(
                    icon: SourceKind.call.icon,
                    title: "No calls yet",
                    message: "Start a session in MajorTom Calls, or save words on your phone and sync them here."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        ForEach(people(in: calls), id: \.name) { person in
                            VStack(alignment: .leading, spacing: 22) {
                                SectionHeader(
                                    title: person.name,
                                    trailing: summary(person.calls))
                                LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                                    ForEach(person.calls) { call in
                                        ShowCard(source: call,
                                                 icon: SourceKind.call.icon) { onOpenCall(call) }
                                    }
                                }
                            }
                        }
                    }
                    .padding(30)
                }
                .background(Theme.bg)
            }
        }
        .navigationTitle(SourceKind.call.label)
        .safeAreaInset(edge: .top) { statusBar }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { translateButton }
        }
        .task { sync.start() }
        .onChange(of: sync.outcome) { _, outcome in scheduleDismiss(for: outcome) }
    }

    // MARK: - Grouping

    private struct Person {
        let name: String
        let calls: [Source]
    }

    private func people(in calls: [Source]) -> [Person] {
        Dictionary(grouping: calls) { $0.site.isEmpty ? "Unknown" : $0.site }
            .map { Person(name: $0.key, calls: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { ($0.calls.first?.createdAt ?? .distantPast) > ($1.calls.first?.createdAt ?? .distantPast) }
    }

    private func summary(_ calls: [Source]) -> String {
        "\(calls.count) \(calls.count == 1 ? "conversation" : "conversations")"
    }

    // MARK: - Sync and translation

    private var translateButton: some View {
        Button(action: sync.translateWaiting) {
            HStack(spacing: 6) {
                if sync.translating {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "character.book.closed")
                }
                Text(sync.waiting > 0 ? "Translate \(sync.waiting)" : "Translate")
            }
        }
        .disabled(sync.translating || sync.waiting == 0)
        .help("Fill in translations for anything saved without one, from any source")
    }

    /// Says whether the phone can reach this Mac, because the only other way to
    /// find out is to try from the phone and have it fail.
    private var statusBar: some View {
        HStack(spacing: 8) {
            if let outcome = sync.outcome {
                Image(systemName: outcome.isFailure
                      ? "exclamationmark.triangle" : "checkmark.circle.fill")
                    .foregroundStyle(outcome.isFailure ? Theme.accent : Theme.success)
                Text(outcome.message)
            } else if let arrival = sync.lastArrival {
                Image(systemName: "iphone.and.arrow.forward.inward")
                Text(arrival)
            } else {
                Image(systemName: sync.listening ? "wifi" : "wifi.slash")
                    .foregroundStyle(.secondary)
                Text(sync.listening
                     ? "Ready for your phone"
                     : "Not listening — your phone will not find this Mac")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if sync.waiting > 0 && !sync.translating {
                Text("\(sync.waiting) waiting for a translation")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 30)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func scheduleDismiss(for outcome: PhoneSync.Outcome?) {
        dismissTask?.cancel()
        guard let outcome, !outcome.isFailure else { return }
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            sync.dismiss()
        }
    }
}
