import MajorTomStyle
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var phone: PhoneSync
    let open: (SidebarItem) -> Void
    let openSource: (Source) -> Void

    private let columns = [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20),
                           GridItem(.flexible(), spacing: 20)]

    var body: some View {
        let stats = store.stats

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(stats)

                if let outcome = phone.outcome {
                    Banner(message: outcome.message, isFailure: outcome.isFailure) { phone.dismiss() }
                }

                HStack(alignment: .top, spacing: 20) {
                    reviewTile(stats)
                    progressCard(stats)
                        .frame(width: 320)
                }
                .frame(height: 250)

                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(SourceKind.captured, id: \.self) { kind in
                        kindTile(kind)
                    }
                }

                fresh(stats)
            }
            .padding(32)
        }
        .background(Palette.background)
        .navigationTitle("Home")
    }

    private func header(_ stats: Stats) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(greeting).font(.rounded(34, .heavy))
            Spacer()
            if stats.streak >= 2 {
                Label("\(stats.streak) days in a row", systemImage: "flame.fill")
                    .font(.rounded(14, .bold))
                    .labelStyle(StreakLabelStyle())
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Palette.card, in: Capsule())
            }
        }
    }

    /// German on purpose: the one line of the app you read every time.
    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11: return "Guten Morgen"
        case 11..<18: return "Guten Tag"
        default: return "Guten Abend"
        }
    }

    private func reviewTile(_ stats: Stats) -> some View {
        let due = store.dueItems(limit: 40)
        let from = Array(NSOrderedSet(array: due.map(\.sourceTitle))) as? [String] ?? []

        return VStack(alignment: .leading, spacing: 8) {
            Text(stats.due > 0 ? "Review time" : "All caught up")
                .font(.rounded(16, .bold)).opacity(0.85)
            Text(stats.due > 0 ? "\(stats.due) \(stats.due == 1 ? "word" : "words")" : "Nothing due")
                .font(.rounded(56, .heavy))
                .minimumScaleFactor(0.6)
            Text(stats.due > 0
                 ? "From \(ListFormatter.localizedString(byJoining: Array(from.prefix(3)))). About \(max(1, stats.due / 3)) min."
                 : "New words become reviewable once they have a translation.")
                .font(.rounded(15)).opacity(0.85)
                .lineLimit(2)
                .frame(maxWidth: 380, alignment: .leading)
            Spacer(minLength: 0)
            if stats.due > 0 {
                Button("Let’s go") { open(.review) }
                    .buttonStyle(ProminentButtonStyle(fill: .white, ink: Palette.accentText))
                    .keyboardShortcut(.space, modifiers: [])
            }
        }
        .foregroundStyle(.white)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.accent, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            // Only when there is room beside the text; never on top of it.
            GeometryReader { proxy in
                if let next = due.first, proxy.size.width > 640 {
                    PreviewCard(item: next)
                        .padding(.trailing, 40)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                }
            }
        }
    }

    private func progressCard(_ stats: Stats) -> some View {
        let reviewed = Double(stats.reviewedToday)
        let learned = Double(stats.learned)
        return HStack(spacing: 22) {
            ZStack {
                Ring(progress: reviewed / max(1, reviewed + Double(stats.due)), color: Palette.accent, lineWidth: 12)
                    .frame(width: 118, height: 118)
                Ring(progress: learned / max(1, learned + Double(stats.learning)), color: Palette.good, lineWidth: 12)
                    .frame(width: 80, height: 80)
            }
            VStack(alignment: .leading, spacing: 14) {
                figure("\(stats.reviewedToday)", "reviewed today", Palette.accentText)
                figure("\(stats.learned)", "learned", Palette.goodText)
                figure("\(stats.learning)", "still learning", Palette.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .card()
    }

    private func figure(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.rounded(20, .heavy)).foregroundStyle(color)
            Text(label).font(.rounded(13)).foregroundStyle(Palette.secondary)
        }
    }

    private func kindTile(_ kind: SourceKind) -> some View {
        let sources = store.sources(of: kind)
        let items = sources.reduce(0) { $0 + $1.itemCount }
        let noun: String = switch kind {
        case .show: sources.count == 1 ? "show" : "shows"
        case .call: sources.count == 1 ? "call" : "calls"
        case .book: sources.count == 1 ? "book" : "books"
        case .own: "list"
        }
        return Tile(tint: kind.tint, height: 150, action: { open(SidebarItem(kind)) }) {
            Image(systemName: kind.icon)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(Palette.card.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.bottom, 8)
            Text(kind.label).font(.rounded(22, .heavy))
            Text("\(sources.count) \(noun) · \(items) saved").font(.rounded(14, .semibold)).opacity(0.8)
        }
    }

    @ViewBuilder
    private func fresh(_ stats: Stats) -> some View {
        let recent = store.recentItems(limit: 8)
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Recently saved")
                FlowLayout(spacing: 10, lineSpacing: 10) {
                    ForEach(recent) { item in
                        Button {
                            if let source = store.sources.first(where: { $0.id == item.sourceID }) {
                                openSource(source)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(item.text).font(.rounded(15, .bold))
                                if !item.translation.isEmpty {
                                    Text(item.translation).font(.rounded(15)).foregroundStyle(Palette.secondary)
                                }
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .background(Palette.card, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("From \(item.sourceTitle)")
                    }
                    if stats.untranslated > 0 {
                        translateChip(stats.untranslated)
                    }
                }
            }
        }
    }

    private func translateChip(_ count: Int) -> some View {
        Button(action: phone.translateWaiting) {
            HStack(spacing: 8) {
                if phone.translating {
                    ProgressView().controlSize(.small)
                    Text("Translating…")
                } else {
                    Image(systemName: "character.book.closed.fill")
                    Text("Translate \(count) waiting")
                }
            }
            .font(.rounded(14, .bold))
            .foregroundStyle(Palette.shows.ink)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(Palette.shows.fill, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(phone.translating)
        .help("Fill in translations for anything saved without one, from any source")
    }
}

/// The next word up, peeking out of the review tile.
private struct PreviewCard: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.text).font(.rounded(24, .heavy)).foregroundStyle(Palette.text)
            Text(item.context.isEmpty ? item.sourceTitle : item.context)
                .font(.rounded(13))
                .foregroundStyle(Palette.secondary)
                .lineLimit(2)
        }
        .padding(20)
        .frame(width: 220, height: 130, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Palette.shows.fill)
                .rotationEffect(.degrees(8))
        )
        .rotationEffect(.degrees(3))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        .accessibilityHidden(true)
    }
}

private struct StreakLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 7) {
            configuration.icon.foregroundStyle(Palette.warm)
            configuration.title
        }
    }
}
