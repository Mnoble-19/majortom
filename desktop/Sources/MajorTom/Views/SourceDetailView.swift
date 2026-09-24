import MajorTomStyle
import SwiftUI

/// One show, call or book: what was saved from it.
struct SourceDetailView: View {
    @EnvironmentObject private var store: Store
    let source: Source
    @State private var reviewing = false

    var body: some View {
        let items = store.items(in: source)
        // The route carries the source as it was when opened; counts come from
        // the live copy so they move as words are learned or deleted.
        let live = store.sources.first { $0.id == source.id } ?? source

        WordBrowser(items: items) { header(live) }
            .navigationTitle(source.title)
            .sheet(isPresented: $reviewing) {
                ReviewView(source: live) { reviewing = false }
                    .frame(minWidth: 760, minHeight: 640)
            }
    }

    private func header(_ source: Source) -> some View {
        let due = store.dueItems(in: source, limit: 100).count

        return HStack(alignment: .center, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text(subtitle(source)).font(.rounded(15, .semibold)).opacity(0.8)
                Text(source.title)
                    .font(.rounded(32, .heavy))
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            Spacer()
            ZStack {
                Ring(progress: source.progress, color: Palette.good, lineWidth: 9)
                Text("\(source.learnedCount)/\(source.itemCount)")
                    .font(.rounded(14, .heavy))
                    .monospacedDigit()
            }
            .frame(width: 76, height: 76)
            .help("\(source.learnedCount) of \(source.itemCount) learned")

            if due > 0 {
                Button("Review \(due)") { reviewing = true }
                    .buttonStyle(ProminentButtonStyle(fill: source.kind.tint.ink, ink: source.kind.tint.fill))
            }
        }
        .foregroundStyle(source.kind.tint.ink)
        .padding(26)
        .background(source.kind.tint.fill, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private func subtitle(_ source: Source) -> String {
        switch source.kind {
        case .show: return "\(Platform.displayName(for: source.site)) · \(source.lastSavedAt.relativeDay)"
        case .call: return "With \(source.site) · \(source.createdAt.relativeDay)"
        case .book: return source.site.isEmpty ? "Book" : source.site
        }
    }
}

struct AllWordsView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        let items = store.allItems()

        WordBrowser(items: items, showsSource: true) {
            PageTitle(title: "All words", subtitle: "\(items.count) saved, newest first")
        }
        .navigationTitle("All words")
    }
}
