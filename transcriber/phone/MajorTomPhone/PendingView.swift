import MajorTomStyle
import SwiftUI

/// What is waiting to go to the Mac, and the one button that sends it.
struct PendingView: View {
    let pending: PendingWords
    let sync: SyncModel

    var body: some View {
        List {
            Section { macCard }
                .listRowBackground(Palette.card)

            if pending.sessions.isEmpty {
                ContentUnavailableView(
                    "Nothing waiting", systemImage: "tray",
                    description: Text("Words you tap during a conversation collect here until you send them."))
                    .listRowBackground(Color.clear)
            }

            ForEach(pending.sessions) { session in
                Section {
                    ForEach(session.words, id: \.text) { word in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(word.text).font(.rounded(19, .heavy))
                            Text(word.sentence)
                                .font(.rounded(14))
                                .foregroundStyle(Palette.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 4)
                        .swipeActions {
                            Button(role: .destructive) {
                                pending.remove(word.text, from: session.id)
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                } header: {
                    Text("\(session.person) · \(session.startedAt.formatted(.relative(presentation: .named)))")
                        .font(.rounded(13, .bold))
                }
                .listRowBackground(Palette.card)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle("Waiting")
        .onAppear { sync.startLooking() }
        .onDisappear { sync.stopLooking() }
    }

    @ViewBuilder
    private var macCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if sync.macs.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Looking for your Mac…").font(.rounded(16, .bold))
                        Text("Open MajorTom on it, on the same Wi‑Fi.")
                            .font(.rounded(13))
                            .foregroundStyle(Palette.secondary)
                    }
                }
            }

            ForEach(sync.macs) { mac in
                HStack(spacing: 12) {
                    Image(systemName: "laptopcomputer")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Palette.accentText)
                        .frame(width: 42, height: 42)
                        .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mac.name).font(.rounded(16, .bold))
                        Text("Found nearby").font(.rounded(13)).foregroundStyle(Palette.goodText)
                    }
                }
                Button {
                    Task { await sync.send(pending, to: mac) }
                } label: {
                    HStack {
                        if sync.state == .sending { ProgressView().tint(.white) }
                        Text(sendLabel).font(.rounded(17, .bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(sync.state == .sending || pending.totalWords == 0)
            }

            switch sync.state {
            case .done(let count):
                Label("Sent \(count) word\(count == 1 ? "" : "s")", systemImage: "checkmark.circle.fill")
                    .font(.rounded(15, .semibold))
                    .foregroundStyle(Palette.goodText)
            case .failed(let why):
                Label(why, systemImage: "exclamationmark.triangle.fill")
                    .font(.rounded(14, .medium))
                    .foregroundStyle(Palette.warmText)
            default:
                EmptyView()
            }
        }
        .padding(.vertical, 8)
    }

    private var sendLabel: String {
        if sync.state == .sending { return "Sending…" }
        let n = pending.totalWords
        return n == 0 ? "Nothing to send" : "Send \(n) word\(n == 1 ? "" : "s")"
    }
}
