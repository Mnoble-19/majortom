import MajorTomStyle
import SwiftUI

/// The platforms you have watched on, then recent episodes from any of them.
struct ShowsView: View {
    @EnvironmentObject private var store: Store
    let openPlatform: (Platform) -> Void
    let openShow: (Source) -> Void

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 20)]

    var body: some View {
        let platforms = store.platforms(of: .show)

        Group {
            if platforms.isEmpty {
                EmptyState(icon: SourceKind.show.icon, title: "No shows yet",
                           message: "Click a word in the subtitles while watching and it lands here.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        HStack(alignment: .bottom) {
                            PageTitle(title: "Shows",
                                      subtitle: "\(platforms.count) \(platforms.count == 1 ? "platform" : "platforms")")
                            Spacer()
                            TranslateButton(scope: .kind(.show))
                        }
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(platforms) { platform in
                                Tile(tint: Palette.shows, height: 150, action: { openPlatform(platform) }) {
                                    Text(platform.name).font(.rounded(26, .heavy)).lineLimit(1)
                                    Spacer(minLength: 0)
                                    Text("\(platform.showCount) \(platform.showCount == 1 ? "show" : "shows") · \(platform.wordCount) saved")
                                        .font(.rounded(14, .semibold)).opacity(0.8)
                                }
                            }
                        }

                        SectionHeader(title: "Recently watched")
                        SourceGrid(sources: Array(store.sources(of: .show).prefix(8)), showsPlatform: true,
                                   open: openShow)
                    }
                    .padding(32)
                }
                .background(Palette.background)
            }
        }
        .navigationTitle("Shows")
    }
}

/// Every show watched on one platform.
struct PlatformView: View {
    @EnvironmentObject private var store: Store
    let site: String
    let openShow: (Source) -> Void

    var body: some View {
        let shows = store.sources(of: .show, site: site)
        let name = Platform.displayName(for: site)

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                BackButton(label: "Shows")
                PageTitle(title: name,
                          subtitle: "\(shows.count) \(shows.count == 1 ? "show" : "shows") · \(shows.reduce(0) { $0 + $1.itemCount }) saved")
                SourceGrid(sources: shows, open: openShow)
            }
            .padding(32)
        }
        .background(Palette.background)
        .navigationTitle(name)
    }
}

struct PageTitle: View {
    let title: String
    var subtitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.rounded(34, .heavy))
            if !subtitle.isEmpty {
                Text(subtitle).font(.rounded(15, .medium)).foregroundStyle(Palette.secondary)
            }
        }
    }
}

/// Cards for episodes and calls: the title, how much was saved, how much of it
/// is learned.
struct SourceGrid: View {
    let sources: [Source]
    var showsPlatform = false
    let open: (Source) -> Void

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 16)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(sources) { source in
                SourceCard(source: source, showsPlatform: showsPlatform) { open(source) }
            }
        }
    }
}

struct SourceCard: View {
    let source: Source
    var showsPlatform = false
    let open: () -> Void
    @State private var hovering = false
    @State private var deleting = false
    @State private var renaming = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    KindBadge(kind: source.kind, size: 36)
                    Spacer()
                    Ring(progress: source.progress, color: Palette.good, lineWidth: 5)
                        .frame(width: 26, height: 26)
                        .help("\(source.learnedCount) of \(source.itemCount) learned")
                }
                Text(source.cardTitle)
                    .font(.rounded(16, .bold))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    if showsPlatform {
                        Text(Platform.displayName(for: source.site))
                        Text("·")
                    }
                    Text("\(source.itemCount) saved")
                    Spacer()
                    // Two calls with one person on one day differ only by time.
                    Text(source.kind == .call && !source.renamed
                         ? source.createdAt.formatted(date: .omitted, time: .shortened)
                         : source.lastSavedAt.relativeDay)
                }
                .font(.rounded(13, .medium))
                .foregroundStyle(Palette.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(hovering ? Palette.accent : .clear, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .contextMenu {
            Button("Rename…") { renaming = true }
            Button("Delete \(source.kind.noun)…", role: .destructive) { deleting = true }
        }
        .confirmDeleting(source, isPresented: $deleting)
        .renaming(source, isPresented: $renaming)
    }
}
