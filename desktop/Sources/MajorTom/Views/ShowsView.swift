import SwiftUI

struct ShowsView: View {
    @EnvironmentObject private var store: Store
    let onOpen: (Source) -> Void

    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 20)]

    var body: some View {
        let shows = store.sources(of: .show)

        Group {
            if shows.isEmpty {
                EmptyState(
                    icon: "play.rectangle",
                    title: "Nothing saved yet",
                    message: "Click a word in the subtitle overlay while watching and it will appear here."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        SectionHeader(title: "Shows", trailing: "\(shows.count)")
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(shows) { show in
                                ShowCard(source: show) { onOpen(show) }
                            }
                        }

                        let recent = store.recentItems()
                        if !recent.isEmpty {
                            SectionHeader(title: "Recent")
                            VStack(spacing: 0) {
                                ForEach(Array(recent.enumerated()), id: \.element.item.id) { i, row in
                                    RecentRow(item: row.item, show: row.sourceTitle)
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
        .navigationTitle("Shows")
    }
}

private struct RecentRow: View {
    let item: Item
    let show: String
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 18) {
            Text(item.text)
                .font(Theme.serif(16, .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 190, alignment: .leading)
                .lineLimit(1)

            Text(item.translation)
                .font(Theme.ui(15))
                .foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            Text(show)
                .font(Theme.ui(13))
                .foregroundStyle(Theme.faint)
                .frame(width: 210, alignment: .trailing)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(hovering ? Color.white.opacity(0.03) : .clear)
        .onHover { hovering = $0 }
    }
}
