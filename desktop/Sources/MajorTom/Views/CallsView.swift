import MajorTomStyle
import SwiftUI

/// Conversations, grouped by who they were with. Whether a call was on Signal
/// or in a café is not how you would look for it; who you were talking to is.
struct CallsView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var phone: PhoneSync
    let openCall: (Source) -> Void

    var body: some View {
        let calls = store.sources(of: .call)

        Group {
            if calls.isEmpty {
                EmptyState(icon: SourceKind.call.icon, title: "No calls yet",
                           message: "Start a session in MajorTom Calls, or tap words on your phone and sync them here.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        PageTitle(title: "Calls", subtitle: phoneStatus)
                        if let arrival = phone.lastArrival {
                            Banner(message: arrival)
                        }
                        ForEach(people(in: calls), id: \.name) { person in
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(spacing: 12) {
                                    Text(String(person.name.prefix(1)).uppercased())
                                        .font(.rounded(17, .heavy))
                                        .foregroundStyle(Palette.calls.ink)
                                        .frame(width: 38, height: 38)
                                        .background(Palette.calls.fill, in: Circle())
                                    SectionHeader(title: person.name,
                                                  trailing: "\(person.calls.count) \(person.calls.count == 1 ? "conversation" : "conversations")")
                                }
                                SourceGrid(sources: person.calls, open: openCall)
                            }
                        }
                    }
                    .padding(32)
                }
                .background(Palette.background)
            }
        }
        .navigationTitle("Calls")
    }

    /// Whether the phone can reach this Mac, because the only other way to
    /// find out is to try from the phone and have it fail.
    private var phoneStatus: String {
        phone.listening ? "Ready for your phone" : "Not listening — your phone will not find this Mac"
    }

    private struct Person {
        let name: String
        let calls: [Source]
    }

    private func people(in calls: [Source]) -> [Person] {
        Dictionary(grouping: calls) { $0.site.isEmpty ? "Unknown" : $0.site }
            .map { Person(name: $0.key, calls: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { ($0.calls.first?.createdAt ?? .distantPast) > ($1.calls.first?.createdAt ?? .distantPast) }
    }
}
