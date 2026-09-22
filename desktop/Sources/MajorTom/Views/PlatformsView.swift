import SwiftUI

/// Landing screen for a source kind: the platforms you have watched on, plus
/// recent episodes from any of them.
struct PlatformsView: View {
    @EnvironmentObject private var store: Store
    let kind: SourceKind
    let onOpenPlatform: (Platform) -> Void
    let onOpenShow: (Source) -> Void

    private let columns = [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 20)]
    private let recentLimit = 8

    var body: some View {
        let platforms = store.platforms(of: kind)

        Group {
            if platforms.isEmpty {
                EmptyState(
                    icon: "play.rectangle",
                    title: "Nothing saved yet",
                    message: "Click a word in the subtitle overlay while watching and it will appear here."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        SectionHeader(title: "Platforms", trailing: "\(platforms.count)")
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(platforms) { platform in
                                PlatformCard(platform: platform) { onOpenPlatform(platform) }
                            }
                        }

                        let recent = Array(store.sources(of: kind).prefix(recentLimit))
                        if !recent.isEmpty {
                            SectionHeader(title: "Recent")
                            VStack(spacing: 0) {
                                ForEach(Array(recent.enumerated()), id: \.element.id) { i, source in
                                    RecentShowRow(source: source) { onOpenShow(source) }
                                    if i < recent.count - 1 {
                                        Divider().overlay(Theme.border).padding(.horizontal, 18)
                                    }
                                }
                            }
                            .cardSurface()
                        }
                    }
                    .padding(30)
                }
                .background(Theme.bg)
            }
        }
        .navigationTitle(kind.label)
    }
}

/// One platform's shows, same cards as the landing grid but smaller.
struct PlatformDetailView: View {
    @EnvironmentObject private var store: Store
    let kind: SourceKind
    let site: String
    let onOpenShow: (Source) -> Void

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 16)]

    var body: some View {
        let shows = store.sources(of: kind, site: site)
        let name = Platform.displayName(for: site)

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(name)
                        .font(Theme.serif(30, .semibold))
                        .foregroundStyle(Theme.text)
                    Text("\(shows.count) \(shows.count == 1 ? "show" : "shows") · \(shows.reduce(0) { $0 + $1.wordCount }) words")
                        .font(Theme.ui(14))
                        .foregroundStyle(Theme.faint)
                }

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(shows) { show in
                        ShowCard(source: show) { onOpenShow(show) }
                    }
                }
            }
            .padding(30)
        }
        .background(Theme.bg)
        .navigationTitle(name)
    }
}
